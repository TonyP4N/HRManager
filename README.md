# 🏢 HRManager

This repository contains the **HRManager** Solidity smart contract, designed to implement a **Human Resources (HR) Payment System** on the **Optimism blockchain**. It enables HR managers to efficiently manage employee registrations, terminations, and salary withdrawals, while ensuring secure and transparent payments.

---

## 🚀 Features

### 🔒 Role-Based Access Control

- **HR Manager**:
  - Register new employees and set their weekly salaries.
  - Terminate employees and stop their salary accrual.
- **Employees**:
  - Withdraw accrued salaries in their preferred currency.
  - Toggle salary payment preference between **USDC** and **ETH**.

---

### 👥 Employee Management

- **Register Employee**: Add an employee with their weekly USD salary. Re-registering starts salary accrual afresh.
- **Terminate Employee**: Stops salary accrual for an employee and emits a termination event.

---

### 💸 Salary Management

- **Continuous Salary Accrual**: Employees' salaries accrue linearly based on time (e.g., 2 days = 2/7th of weekly salary).
- **Flexible Withdrawals**:
  - Employees can withdraw salaries in **USDC** (default) or **ETH**.
  - Integration with Uniswap V3 AMM for real-time USDC-to-ETH conversion.
  - Chainlink Oracle ensures accurate ETH/USD price feeds for withdrawals.
- **Automatic Withdrawal**:
  - Any pending salary is automatically withdrawn when switching payment currencies.

---

### 🔄 Currency Switching

- Employees can **toggle their payment currency** between:
  - **USDC (Default)**: Fast and stable currency.
  - **ETH**: Real-time exchange through Uniswap.
- Triggers the `CurrencySwitched` event for tracking.

---

## 🛠️ Technical Details

- **Blockchain**: Optimism Layer 2.
- **Dependencies**:
  - **Chainlink Oracle** for fetching ETH/USD price feeds.
  - **Uniswap V3 Router** for AMM-based USDC-to-ETH swaps.
- **Precision**:
  - USDC: 6 decimals.
  - ETH: 18 decimals.

---

## 📑 Installation & Usage

### Prerequisites

- [Foundry](https://github.com/foundry-rs/foundry)
- [Node.js](https://nodejs.org/) (for additional tools if needed)

### Installation Steps

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/TonyP4N/HRManager.git
   cd HRManager
2. **Install Dependencies**:
    Run the following commands to install the required dependencies for the project:
    
    ```bash
    bash install.sh
3. **Build the Contracts**:
    ```bash
    forge build
4. **Test the Contracts**:
    ```bash
    forge test

---

## 📚 Function Implementations

### `registerEmployee(address _employee, uint256 _weeklyUsdSalary)`

- **Access Control**: Only HR manager.
- **Purpose**: Registers a new employee with a weekly USD salary.
- **Validation**: Salary must be greater than zero; reverts if employee is already registered.
- **Updates**:
  - Sets employee details in the `Employee` struct.
  - Increments `activeEmployeeCount`.
- **Event**: Emits `EmployeeRegistered`.

### `terminateEmployee(address _employee)`

- **Access Control**: Only HR manager.
- **Purpose**: Terminates an employee.
- **Validation**: Reverts if employee is not registered.
- **Updates**:
  - Calculates unclaimed salary and updates `totalUsdSalaries`.
  - Sets `isActive` to `false` and updates `terminatedAt`.
  - Decrements `activeEmployeeCount`.
- **Event**: Emits `EmployeeTerminated`.

### `withdrawSalary()`

- **Access Control**: Only callable by employees.
- **Purpose**: Allows employees to withdraw accumulated salary.
- **Functionality**:
  - Calculates unclaimed salary based on time worked.
  - Resets `lastWithdrawalTime` and `totalUsdSalaries`.
  - Distributes salary in USDC or swaps to ETH via Uniswap if `prefersEth` is `true`.
- **Security**: Uses `nonReentrant` to prevent reentrancy attacks.
- **Event**: Emits `SalaryWithdrawn`.

### `switchCurrency()`

- **Access Control**: Only callable by employees.
- **Purpose**: Toggles salary payment between USDC and ETH.
- **Functionality**:
  - Calls `withdrawSalary()` before switching.
  - Toggles `prefersEth`.
- **Event**: Emits `CurrencySwitched`.

### `salaryAvailable(address _employee) → uint256`

- **Purpose**: Returns the amount of salary available for withdrawal.
- **Functionality**:
  - Calculates accumulated salary.
    - **Salary Calculation**:
      - Calculates the time since the last withdrawal.
      - Determines `unclaimedSalary` based on `timeDiff` and `weeklyUsdSalary`.
      - Calculates `totalAmount` as the sum of `unclaimedSalary` and any `totalUsdSalaries`.
  - Converts amount to ETH if `prefersEth` is `true`.

### `hrManager() → address`

- **Purpose**: Returns the HR manager's address.

### `getActiveEmployeeCount() → uint256`

- **Purpose**: Returns the count of active employees.

### `getEmployeeInfo(address _employee) → (uint256, uint256, uint256)`

- **Purpose**: Retrieves employee's salary, employment start, and termination time.
- **Functionality**:
  - If the employee is not active, returns zeros for all values.
  - Otherwise, returns:
    - `weeklyUsdSalary`
    - `employedSince`
    - `terminatedAt`

---

## 🔌 AMM and Oracle Integration

### Uniswap V3 Integration

- **Function**: `swapUSDCToETH(uint256 usdcAmount)`
- **Purpose**: Swaps USDC to ETH when employees prefer to receive their salary in ETH.
- **Implementation**:
  - **Approvals**:
    - Uses `safeIncreaseAllowance` to allow the Uniswap router to spend USDC.
  - **Slippage Consideration**:
    - Calculates `expectedEthAmount` based on the current ETH price.
    - Sets `amountOutMinimum` to 98% of `expectedEthAmount` to allow up to 2% slippage.
  - **Swap Execution**:
    - Constructs `ExactInputSingleParams` for the Uniswap router.
    - Calls `exactInputSingle` on the Uniswap router to execute the swap.
  - **ETH Handling**:
    - Unwraps WETH to ETH using `IWETH9.withdraw(wethReceived)`.
    - Returns the amount of ETH received.

### Chainlink ETH/USD Price Feed

- **Function**: `getLatestETHPrice()`
- **Purpose**: Retrieves the latest ETH price in USD.
- **Implementation**:
  - Calls `latestRoundData()` on the price feed.
  - Ensures the retrieved price is valid (greater than zero).
  - Adjusts price to 18 decimals for consistency.

---

## ⚠️ Error Handling

- **`NotAuthorized`**
  - Thrown when an unauthorized user attempts to call a restricted function.
- **`EmployeeAlreadyRegistered`**
  - Thrown when trying to register an employee who is already registered.
- **`EmployeeNotRegistered`**
  - Thrown when attempting to terminate or interact with an employee who is not registered.
- **Invalid Price From Oracle**
  - Thrown when the price retrieved from the oracle is invalid.
- **Slippage Protection**
  - Swap reverts if slippage exceeds 2% during USDC to ETH conversion.

---

## ✨ Key Events

The contract emits several events to enable tracking of important actions:

- **`EmployeeRegistered(address indexed employee, uint256 weeklyUsdSalary)`**
  - Emitted when a new employee is registered.
- **`EmployeeTerminated(address indexed employee)`**
  - Emitted when an employee is terminated.
- **`SalaryWithdrawn(address indexed employee, bool isEth, uint256 amount)`**
  - Emitted when an employee withdraws their salary.
- **`CurrencySwitched(address indexed employee, bool isEth)`**
  - Emitted when an employee switches their salary currency preference.

---

## 🔒 Security and Additional Details

- **Security**:
  - Access control enforced via modifiers.
  - Reentrancy protection on critical functions.
  - Uses `SafeERC20` for secure token operations.
- **Employee Struct Fields**:
  - `weeklyUsdSalary`: The weekly salary in USD (scaled to 18 decimals).
  - `employedSince`: Timestamp of when the employee was registered.
  - `terminatedAt`: Timestamp of when the employee was terminated (0 if active).
  - `lastWithdrawalTime`: Timestamp of the last salary withdrawal.
  - `totalUsdSalaries`: Accumulated unclaimed salary in USD.
  - `prefersEth`: Indicates if the employee prefers salary in ETH (`true`) or USDC (`false`).
  - `isActive`: Indicates if the employee is currently active.
- **Salary Accumulation**:
  - Salary accrues continuously over time, regardless of non-working hours.

---

## 📜 License

This project is licensed under the **MIT License**. See the `LICENSE` file for details.
