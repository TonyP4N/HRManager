/// @notice This is a test contract for the HumanResources contract
/// You can either run this test for a contract deployed on a local fork or for a contract deployed on Optimism
/// To use a local fork, start anvil using anvil --rpc-url $RPC_URL where RPC_URL should point to an Optimism RPC.
/// Deploy your contract on the local fork and set the following environment variables:
/// - HR_CONTRACT: the address of the deployed contract
/// - ETH_RPC_URL: the RPC URL of the local fork (likely http://localhost:8545)
/// To run on Optimism, you will need to set the same environment variables, but with the address of the deployed contract on Optimism
/// and ETH_RPC_URL should point to the Optimism RPC.
/// Once the environment variables are set, you can run the tests using forge test --mp test/HumanResourcesTests.t.sol
/// assuming that you copied the file into the test folder of your project.

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @notice You may need to change these import statements depending on your project structure and where you use this test
import {Test, stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {HumanResources, IHumanResources} from "../src/HumanResources.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract HumanResourcesTest is Test {
    using stdStorage for StdStorage;

    address internal constant _WETH =
        0x4200000000000000000000000000000000000006;
    address internal constant _USDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    AggregatorV3Interface internal constant _ETH_USD_FEED =
        AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    HumanResources public humanResources;

    address public hrManager;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public aliceSalary = 2100e18;
    uint256 public bobSalary = 700e18;

    uint256 ethPrice;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        humanResources = HumanResources(payable(vm.envAddress("HR_CONTRACT")));
        (, int256 answer, , , ) = _ETH_USD_FEED.latestRoundData();
        uint256 feedDecimals = _ETH_USD_FEED.decimals();
        ethPrice = uint256(answer) * 10 ** (18 - feedDecimals);
        hrManager = humanResources.hrManager();
    }

    function test_registerEmployee() public {
        _registerEmployee(alice, aliceSalary);
        assertEq(humanResources.getActiveEmployeeCount(), 1);

        uint256 currentTime = block.timestamp;

        (
            uint256 weeklySalary,
            uint256 employedSince,
            uint256 terminatedAt
        ) = humanResources.getEmployeeInfo(alice);
        assertEq(weeklySalary, aliceSalary);
        assertEq(employedSince, currentTime);
        assertEq(terminatedAt, 0);

        skip(10 hours);

        _registerEmployee(bob, bobSalary);

        (weeklySalary, employedSince, terminatedAt) = humanResources
            .getEmployeeInfo(bob);
        assertEq(humanResources.getActiveEmployeeCount(), 2);

        assertEq(weeklySalary, bobSalary);
        assertEq(employedSince, currentTime + 10 hours);
        assertEq(terminatedAt, 0);
    }

    function test_registerEmployee_twice() public {
        _registerEmployee(alice, aliceSalary);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        _registerEmployee(alice, aliceSalary);
    }

    function test_salaryAvailable_usdc() public {
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        assertEq(
            humanResources.salaryAvailable(alice),
            ((aliceSalary / 1e12) * 2) / 7
        );

        skip(5 days);
        assertEq(humanResources.salaryAvailable(alice), aliceSalary / 1e12);
    }

    function test_salaryAvailable_eth() public {
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
    }

    function test_withdrawSalary_usdc() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            ((aliceSalary / 1e12) * 2) / 7
        );

        skip(5 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(address(alice)), aliceSalary / 1e12);
    }

    function test_withdrawSalary_eth() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
    }

    function test_reregisterEmployee() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        skip(1 days);
        _registerEmployee(alice, aliceSalary * 2);

        skip(5 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedSalary = ((aliceSalary * 2) / 7) +
            ((aliceSalary * 2 * 5) / 7);
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            expectedSalary / 1e12
        );
    }

    function _registerEmployee(address employeeAddress, uint256 salary) public {
        vm.prank(hrManager);
        humanResources.registerEmployee(employeeAddress, salary);
    }

    function _mintTokensFor(
        address token_,
        address account_,
        uint256 amount_
    ) internal {
        stdstore
            .target(token_)
            .sig(IERC20(token_).balanceOf.selector)
            .with_key(account_)
            .checked_write(amount_);
    }
}