// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

import {BaseImmutableAdminUpgradeabilityProxy} from './BaseImmutableAdminUpgradeabilityProxy.sol';
import {InitializableUpgradeabilityProxy} from "../../../dependencies/upgradability/InitializableUpgradeabilityProxy.sol";

/**
 * @title InitializableAdminUpgradeabilityProxy
 * @dev Extends BaseAdminUpgradeabilityProxy with an initializer function
 */
contract InitializableImmutableAdminUpgradeabilityProxy is BaseImmutableAdminUpgradeabilityProxy, InitializableUpgradeabilityProxy {
  constructor(address admin) public BaseImmutableAdminUpgradeabilityProxy(admin) {}

  /**
   * @dev Only fall back when the sender is not the admin.
   */
  function _willFallback() internal override(BaseImmutableAdminUpgradeabilityProxy, Proxy) {
    BaseImmutableAdminUpgradeabilityProxy._willFallback();
  }
}