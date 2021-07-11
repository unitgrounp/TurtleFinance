// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

interface ITurtleFinanceTokenPoolBank {

    function mainContractAddress() external view returns (address);

    function name() external view returns (string memory);

    function create(address token) external;

    function balanceOf(address token) external view returns (uint256);

    function save(address token, uint256 quantity) external;

    function take(address token, uint256 quantity) external;

    function destroy(address token) external;

}