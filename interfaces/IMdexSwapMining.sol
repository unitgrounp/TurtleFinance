// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface IMdexSwapMining {

    function getUserReward(uint256 pid) external view returns (uint256, uint256);

    function takerWithdraw() external;

    function mdx() external returns (address);

}