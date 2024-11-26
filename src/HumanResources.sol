// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IHumanResources.sol";

import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {AggregatorV3Interface} from "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Security
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Address} from "../lib/openzeppelin-contracts/contracts/utils/Address.sol";


interface IWETH9 {
    function withdraw(uint256 wad) external;
} 


contract HumanResources is IHumanResources, ReentrancyGuard {

    address public immutable hrManager;
    uint256 private weeklyUsdSalary;
    uint256 private activeEmployeeCount;
    uint256 private unclaimedUsdSalaries;

    AggregatorV3Interface internal priceFeed;
    ISwapRouter public immutable swapRouter;

    IERC20 public immutable usdcToken;
    address public immutable WETH9;

    uint256 private constant SECONDS_IN_A_WEEK = 604800;

    mapping(address => bool) private isFirstTimeRegistered;
    mapping(address => Employee) private employees;

    // Security
    using Address for address payable;
    using SafeERC20 for IERC20;

    struct Employee {
        uint256 weeklyUsdSalary;
        uint256 employedSince;
        uint256 terminatedAt;
        uint256 lastWithdrawalTime;
        uint256 totalUsdSalaries;
        uint activeEmployeeCount;
        bool isActive;
        bool prefersEth;
    }
    

    modifier onlyHRManager() {
        if (msg.sender != hrManager) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyEmployee() {
        Employee storage emp = employees[msg.sender]; //store employee info to a storage variable(Database)
        if (!emp.isActive && emp.employedSince == 0 && emp.totalUsdSalaries == 0) {
            revert NotAuthorized();
        } // not active, not employed, no salary
        _;
    }

    constructor() {
        hrManager = msg.sender;
        priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        usdcToken = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85); // USDC address on Optimism
        WETH9 = 0x4200000000000000000000000000000000000006; // WETH address on Optimism
    }


    function registerEmployee(address _employee, uint256 _weeklyUsdSalary) external override onlyHRManager {
        require(_weeklyUsdSalary > 0, "Salary must be greater than zero");
        if (employees[_employee].isActive) {
            revert EmployeeAlreadyRegistered();
        }

        employees[_employee].isActive = true;
        Employee storage emp = employees[_employee]; // register employee to database

        emp.weeklyUsdSalary = _weeklyUsdSalary;
        emp.employedSince = block.timestamp;
        emp.lastWithdrawalTime = block.timestamp;
        emp.prefersEth = false;

        activeEmployeeCount += 1;

        emit EmployeeRegistered(_employee, _weeklyUsdSalary);
        
    }


    function terminateEmployee(address _employee) external override onlyHRManager {
        if (!employees[_employee].isActive) {
            revert EmployeeNotRegistered();
        }

        Employee storage emp = employees[_employee]; // get employee info from database

        // Calculate salary
        uint256 terminateTime = block.timestamp;
        uint256 hireTime = terminateTime - emp.lastWithdrawalTime;
        uint256 unclaimedSalary = (hireTime * emp.weeklyUsdSalary) / SECONDS_IN_A_WEEK;
        emp.totalUsdSalaries += unclaimedSalary;

        emp.isActive = false;
        emp.terminatedAt = block.timestamp;
        emp.lastWithdrawalTime = block.timestamp;

        activeEmployeeCount -= 1;

        emit EmployeeTerminated(_employee);
        
    }


    function getLatestETHPrice() public view returns (uint256) {
        (
            , // roundId
            int256 price, // price in USD with 8 decimals
            , // startedAt
            , // updatedAt
            // answeredInRound
        ) = priceFeed.latestRoundData();

        require(price > 0, "Invalid price from oracle");

        uint256 decimalsNum = priceFeed.decimals();
        return uint256(price) * (10**(18 - decimalsNum)); // Convert price to 18 decimals
    }
    
    
    function swapUSDCToETH(uint256 usdcAmount) internal returns (uint256 ethAmount) {
        require(usdcAmount > 0, "Amount must be greater than zero");
        
        // Approve the router to spend USDC
        usdcToken.safeIncreaseAllowance(address(swapRouter), usdcAmount / 1e12); // USDC has 6 decimals

        // Consider slippage
        uint256 ethPrice = getLatestETHPrice(); // 18 decimals
        uint256 expectedEthAmount = ((usdcAmount * 1e18) / ethPrice); // Convert to USDC decimals (6)
        uint256 expectedAmountOutMinimum = (expectedEthAmount * 98) / 100; // 2% slippage

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: WETH9,
            fee: 3000, // Pool fee: 0.3%
            recipient: address(this),
            deadline: block.timestamp + 15, // Transaction must execute within 15 seconds
            amountIn: usdcAmount / 1e12, // Convert to USDC decimals (6)
            amountOutMinimum: expectedAmountOutMinimum, // The minimum amount of WETH9 we want to receive
            sqrtPriceLimitX96: 0
        });

        uint256 wethReceived = swapRouter.exactInputSingle(params);

        // Unwrap WETH to ETH
        IWETH9(WETH9).withdraw(wethReceived);

        return wethReceived;
    }


    function switchCurrency() external override onlyEmployee() {
        
        withdrawSalary(); // this is why withdrawSalary is public

        Employee storage emp = employees[msg.sender]; // get employee info from database

        emp.prefersEth = !emp.prefersEth;

        emit CurrencySwitched(msg.sender, emp.prefersEth);
        
    }


    function withdrawSalary() public override onlyEmployee nonReentrant {
        Employee storage emp = employees[msg.sender]; // get employee info from database

        // if (emp.isActive) {
        //     revert ("You are still an active employee");
        // }

        uint256 endTime = emp.isActive ? block.timestamp : emp.terminatedAt;
        uint256 startTime = emp.lastWithdrawalTime;
        uint256 timeDiff = endTime - startTime;
        uint256 unclaimedSalary = (timeDiff * emp.weeklyUsdSalary) / SECONDS_IN_A_WEEK;

        uint256 totalAmount = emp.totalUsdSalaries + unclaimedSalary;

        emp.lastWithdrawalTime = block.timestamp;
        emp.totalUsdSalaries = 0;

        if (emp.prefersEth) {
            uint256 ethAmount = swapUSDCToETH(totalAmount);
            payable(msg.sender).transfer(ethAmount);
            emit SalaryWithdrawn(msg.sender, true, ethAmount);
        } else {
            usdcToken.safeTransfer(msg.sender, totalAmount / 1e12);
            emit SalaryWithdrawn(msg.sender, false, totalAmount / 1e12);
        }

    }


    function salaryAvailable(address _employee) external view override returns (uint256) {

        Employee storage emp = employees[_employee];

        if (!employees[_employee].isActive) {
            return 0;
        }// employee not registered

        // Calculate salary
        uint256 endTime = emp.isActive ? block.timestamp : emp.terminatedAt;
        uint256 startTime = emp.lastWithdrawalTime;
        uint256 timeDiff = endTime - startTime;
        uint256 unclaimedSalary = (timeDiff * emp.weeklyUsdSalary) / SECONDS_IN_A_WEEK;

        uint256 totalAmount = emp.totalUsdSalaries + unclaimedSalary;

        if (emp.prefersEth) {
            uint256 ethAmount = (totalAmount * 1e18) / getLatestETHPrice();
            return ethAmount;
        } else {
            return totalAmount / 1e12;
        }

    }


    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }


    function getEmployeeInfo(address _employee) external view override returns (uint256, uint256, uint256) {
        Employee storage emp = employees[_employee];

        if (!employees[_employee].isActive) {
            return (0, 0, 0);
        }// employee not registered

        return (emp.weeklyUsdSalary, emp.employedSince, emp.terminatedAt);
    }


    receive() external payable {}
}


