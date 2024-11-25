// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IHumanResources.sol";
import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../lib/chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";


contract HumanResources is IHumanResources {

    address public immutable hrManager;
    uint256 private weeklyUsdSalary;
    uint256 private activeEmployeeCount;

    AggregatorV3Interface internal priceFeed;
    ISwapRouter public immutable swapRouter;

    mapping(address => uint256) private employedSince;
    mapping(address => uint256) private terminatedAt;
    mapping(address => uint256) private totalUsdSalaries;
    mapping(address => uint256) private unclaimedUsdSalaries;
    mapping(address => uint256) private weeklyUsdSalaries;
   
    mapping(address => bool) private employee;
    mapping(address => bool) private isFirstTimeRegistered;
    mapping(address => bool) private isFreezedAccSalary;
    mapping(address => uint256) private preferredCurrency; // 1 for USDC, 0 for ETH


    modifier onlyHRManager() {
        if (msg.sender != hrManager) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyEmployee() {
        if (!employee[msg.sender]) {
            revert NotAuthorized();
        }
        _;
    }

    constructor() {
        hrManager = msg.sender;
        priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);
        swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    }


    function registerSalary(address _employee) internal {
        employedSince[_employee] = block.timestamp;
        activeEmployeeCount += 1;
        
    }


    function registerEmployee(address _employee, uint256 _weeklyUsdSalary) external onlyHRManager {
        require(employee[_employee], EmployeeAlreadyRegistered());
        employee[_employee] = true;
        weeklyUsdSalaries[_employee] = _weeklyUsdSalary * 10**18;

        if (isFirstTimeRegistered[_employee]) {
            isFirstTimeRegistered[_employee] = false;
            isFreezedAccSalary[_employee] = false;
            unclaimedUsdSalaries[_employee] = 0; //initialize unclaimed salary
            registerSalary(_employee);
            preferredCurrency[_employee] = 1;

            emit EmployeeRegistered(_employee, weeklyUsdSalary);
        } else {
            isFreezedAccSalary[_employee] = false;
            unclaimedUsdSalaries[_employee] = unclaimedUsdSalaries[_employee] + totalUsdSalaries[_employee]; //keep unclaimed salary tracked
            registerSalary(_employee);
            
            emit EmployeeRegistered(_employee, weeklyUsdSalary);
        }
    }


    function terminateEmployee(address _employee) external onlyHRManager {
        require(!employee[_employee], EmployeeNotRegistered());
        require(isFreezedAccSalary[_employee], EmployeeNotRegistered());
        employee[_employee] = false;
        isFirstTimeRegistered[_employee] = false;
        isFreezedAccSalary[_employee] = true;
        terminatedAt[_employee] = block.timestamp;
        totalUsdSalaries[_employee] = ((terminatedAt[_employee] - employedSince[_employee]) * weeklyUsdSalaries[_employee] / 604800) + unclaimedUsdSalaries[_employee];
        activeEmployeeCount -= 1;

        emit EmployeeTerminated(_employee);
        
    }


    function sendSalary(address payable _employee, uint256 amount) internal {

        _employee.transfer(amount);
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
        return uint256(price) * 10**10; // Convert price to 18 decimals
    }
    
    
    function swapUSDCToETH(uint256 usdcAmount) internal returns (uint256 ethAmount) {
        require(usdcAmount > 0, "Amount must be greater than zero");

        IERC20 usdcToken = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85); // USDC address on Optimism
        usdcToken.approve(address(swapRouter), usdcAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(usdcToken),
            tokenOut: address(0x4200000000000000000000000000000000000006), // WETH address on Optimism
            fee: 3000, // Pool fee: 0.3%
            recipient: address(this),
            deadline: block.timestamp + 15, // Transaction must execute within 15 seconds
            amountIn: usdcAmount,
            amountOutMinimum: (usdcAmount * 10**18) / getLatestETHPrice(), // 2% slippage
            sqrtPriceLimitX96: 0
        });

        // Execute the swap
        ethAmount = swapRouter.exactInputSingle(params);
    }


    function switchCurrency() external onlyEmployee {
        require(employee[msg.sender], "Not authorized");
        require(!isFreezedAccSalary[msg.sender], "You have terminated your contract");

        withdrawSalary();

        if (preferredCurrency[msg.sender] == 1) { 
            preferredCurrency[msg.sender] = 0;
            emit CurrencySwitched(msg.sender, true);
        } else {
            preferredCurrency[msg.sender] = 1;
            emit CurrencySwitched(msg.sender, false);
        }
    }


    function withdrawSalary() public onlyEmployee {
        require(employee[msg.sender], NotAuthorized());
        require(isFreezedAccSalary[msg.sender], "You have not terminated your contract yet");

        if (preferredCurrency[msg.sender] == 1) { // USDC
            sendSalary(payable(msg.sender), totalUsdSalaries[msg.sender]);
            totalUsdSalaries[msg.sender] = 0;
            emit SalaryWithdrawn(msg.sender, false, totalUsdSalaries[msg.sender]);
        } else if (preferredCurrency[msg.sender] == 0) { // ETH
            uint256 ethAmount = swapUSDCToETH(totalUsdSalaries[msg.sender]);
            payable(msg.sender).transfer(ethAmount);
            totalUsdSalaries[msg.sender] = 0;
            emit SalaryWithdrawn(msg.sender, true, ethAmount);
        } else {
            revert("Currency not supported");
        }
    }


    function salaryAvailable(address _employee) external view returns (uint256) {
        require(!isFreezedAccSalary[_employee], "You have not terminated your contract yet");

        if (!employee[_employee]) {
            return 0;
        }

        uint256 timeStampDiff = block.timestamp - employedSince[_employee];
        
        if (preferredCurrency[_employee] == 1) { // USDC
            return (timeStampDiff * weeklyUsdSalaries[_employee]) / 604800;
        } else if (preferredCurrency[_employee] == 0) { // ETH
            uint256 usdcAmount = (timeStampDiff * weeklyUsdSalaries[_employee]) / 604800;
            return (usdcAmount * 10**18) / getLatestETHPrice();
        } else {
            revert("Currency not supported");
        }
    }


    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }


    function getEmployeeInfo(address _employee) external view override returns (uint256, uint256, uint256) {
        if (!employee[_employee]) {
            return (0, 0, 0);
        }
        if (isFreezedAccSalary[_employee]) {
            uint256 salary = ((terminatedAt[_employee] - employedSince[_employee]) * weeklyUsdSalaries[_employee]) / 604800;
            return (salary, employedSince[_employee], terminatedAt[_employee]);
        }
        
        return (weeklyUsdSalaries[_employee], employedSince[_employee], terminatedAt[_employee]);
    }


    receive() external payable {}
}


