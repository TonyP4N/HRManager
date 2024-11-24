#!/bin/bash

forge install uniswap/v3-periphery
forge install smartcontractkit/chainlink
forge install OpenZeppelin/openzeppelin-contracts


if [ $? -eq 0 ]; then
  echo "All dependencies installed successfully!"
else
  echo "Error installing dependencies"
fi
