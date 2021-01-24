// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;

import "../../../dependencies/openzeppelin/math/SafeMath.sol";
import "../../../dependencies/openzeppelin/token/ERC20/IERC20.sol";
import "../../../dependencies/openzeppelin/token/ERC20/SafeERC20.sol";

import "../../../../interfaces/GlobalAddressesProvider/IGlobalAddressesProvider.sol";
import '../../../../interfaces/lendingProtocol/ILendingPool.sol';

import '../interfaces/IFlashLoanReceiver.sol';

abstract contract FlashLoanReceiverBase is IFlashLoanReceiver {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  IGlobalAddressesProvider public immutable override ADDRESSES_PROVIDER;
  ILendingPool public immutable override LENDING_POOL;

  constructor(IGlobalAddressesProvider provider) {
    ADDRESSES_PROVIDER = provider;
    LENDING_POOL = ILendingPool(provider.getLendingPool());
  }
}