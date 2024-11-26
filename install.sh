#!/bin/bash

forge install uniswap/v3-periphery --no-commit
forge install smartcontractkit/chainlink --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit


if [ $? -eq 0 ]; then
  echo "All dependencies installed successfully!"
else
  echo "Error installing dependencies"
fi
