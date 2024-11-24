// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IHumanResources.sol";
import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
} 

abstract contract HumanResources is IHumanResources {

    address public immutable hrManager;
    uint256 private weeklyUsdSalary;
    AggregatorV3Interface internal priceFeed;
    ISwapRouter public immutable swapRouter;

    mapping (address => uint256) private activeDays;
    mapping(address => uint256) private registerTime;
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
    /// The salary accumulates with time (regardless of nights, weekends, and other non-working hours) 
    /// according to the employee's weekly salary
    /// This means that after 2 days, the employee will be able to withdraw 2/7th of their weekly salary
    /// At start, the activive days are 0
        activeDays[_employee] = 0;
        registerTime[_employee] = block.timestamp;
        
    }

    function registerEmployee(address _employee, uint256 weeklyUsdSalary) external onlyHRManager {
        require(employee[_employee], EmployeeAlreadyRegistered());
        employee[_employee] = true;

        if (isFirstTimeRegistered[_employee]) {
            isFirstTimeRegistered[_employee] = false;
            registerSalary(_employee);
            preferredCurrency[_employee] = 1;

            emit EmployeeRegistered(_employee, weeklyUsdSalary);
        } else {
            isFreezedAccSalary[_employee] = false;

            emit EmployeeRegistered(_employee, weeklyUsdSalary);
        }
    }

    function terminateEmployee(address _employee) external onlyHRManager {
        require(!employee[_employee], EmployeeNotRegistered());
        employee[_employee] = false;
        isFirstTimeRegistered[_employee] = false;
        isFreezedAccSalary[_employee] = true;

        emit EmployeeTerminated(_employee);
        
    }

    function sendSalary(address payable _employee, uint256 amount) internal {
        // send USDC to the employee
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

        // Approve Uniswap Router to spend USDC
        IERC20 usdcToken = IERC20(0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85); // USDC address on Optimism
        usdcToken.approve(address(swapRouter), usdcAmount);

        // Define swap parameters
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


    function switchCurrency() external onlyEmployee() {

        require(employee[msg.sender], NotAuthorized());
        require(!isFreezedAccSalary[msg.sender], "You have to terminated your contract first!");
        
           // 1 for USDC, 0 for ETH
        if (preferredCurrency[msg.sender] == 1) {
            preferredCurrency[msg.sender] = 0;
            emit CurrencySwitched(msg.sender, true);
        } else if (preferredCurrency[msg.sender] == 0) {
            preferredCurrency[msg.sender] = 1;
            emit CurrencySwitched(msg.sender, false);
        } else {
            revert("Currency not supported");
        }

        
       withdrawSalary();


    }

    function withdrawSalary() public onlyEmployee {
        require(employee[msg.sender], NotAuthorized());
        require(!isFreezedAccSalary[msg.sender], "You have not terminated your contract yet");

        // Calculate the amount of salary to be paid
        uint256 timeStampDiff = block.timestamp - registerTime[msg.sender];
        uint256 usdcAmount = (timeStampDiff * weeklyUsdSalary) / 604800;

        if (preferredCurrency[msg.sender] == 1) { // USDC
            sendSalary(payable(msg.sender), usdcAmount);
            emit SalaryWithdrawn(msg.sender, false, usdcAmount);
        } else if (preferredCurrency[msg.sender] == 0) { // ETH
            uint256 ethAmount = swapUSDCToETH(usdcAmount);
            payable(msg.sender).transfer(ethAmount);
            emit SalaryWithdrawn(msg.sender, true, ethAmount);
        } else {
            revert("Currency not supported");
        }
    }


    receive() external payable {}
}


