// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;

import '../../../../interfaces/lendingProtocol/ILendingPool.sol';
import "../../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";

/**
 * @title IFlashLoanReceiver interface
 * @notice Interface for the Aave fee IFlashLoanReceiver.
 * @author Aave
 * @dev implement this interface to develop a flashloan-compatible flashLoanReceiver contract
 **/
interface IFlashLoanReceiver {

  function executeOperation(address[] calldata assets, uint256[] calldata amounts, uint256[] calldata premiums, address initiator, bytes calldata params) external returns (bool);

  function ADDRESSES_PROVIDER() external view returns (IGlobalAddressesProvider);

  function LENDING_POOL() external view returns (ILendingPool);
}