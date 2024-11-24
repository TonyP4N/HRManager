# 🏢 HRManager Solidity Project

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
  - Integration with Uniswap AMM for real-time USDC-to-ETH conversion.
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
  - **Uniswap Router** for AMM-based USDC-to-ETH swaps.
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
   ```bash
   forge install
3. **Build the Contracts**:
    ```bash
    forge build

### ✨ Key Events
The contract emits several events to enable tracking of important actions:

- **`EmployeeRegistered`**: Fired when an employee is successfully registered.
- **`EmployeeTerminated`**: Fired when an employee is terminated.
- **`SalaryWithdrawn`**: Fired when an employee withdraws their salary, indicating the currency used.
- **`CurrencySwitched`**: Fired when an employee switches their preferred payment currency.

---

### 📜 License
This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.


