// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface IKswapDexMining {

    function emergencyWithdraw(uint256 pid) external;

    function kst() external view returns (address);

}