// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.7.0;

interface ISIGHHarvester {

    function accureSIGHForLiquidityStream(address user) external;
    function accureSIGHForBorrowingStream(address user) external;

    function claimSIGH(address[] users) onlyOverlyingTokens external;
    function claimMySIGH(address user) onlyOverlyingTokens external;

    function getSighAccured(address account) external view returns (uint);
}
