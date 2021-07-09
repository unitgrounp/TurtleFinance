// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITurtleFinanceTokenPoolBank.sol";
import "./interfaces/ITurtleFinanceMainV1.sol";

contract BankDefault is ITurtleFinanceTokenPoolBank {

    using SafeERC20 for IERC20;

    ITurtleFinanceMainV1 public mainContract;

    constructor(address mainAddr_) {
        mainContract = ITurtleFinanceMainV1(mainAddr_);
    }

    modifier onlyOwner() {
        bool isOwner = mainContract.owner() == msg.sender;
        require(isOwner, "caller is not the owner");
        _;
    }
    modifier onlyMain() {
        bool isMain = address(mainContract) == msg.sender;
        require(isMain, "caller is not the main");
        _;
    }

    function mainContractAddress() override external view returns (address){
        return address(mainContract);
    }

    function name() override external view returns (string memory){
        return "BankDefault";
    }


    function withdrawToken(address token, address payable to, uint256 quantity) public onlyOwner {
        if (token == address(0))
            to.transfer(quantity);
        else
            IERC20(token).safeTransfer(to, quantity);
    }

    function create(address token) onlyMain override external {

    }

    function balanceOf(address token) onlyMain override external view returns (uint256){
        return IERC20(token).balanceOf(address(this));
    }

    function save(address token, uint256 quantity) onlyMain override external {
    }

    function take(address token, uint256 quantity) onlyMain override external {
        IERC20(token).safeTransfer(address(mainContract), quantity);
    }

    function destroy(address token) onlyMain override external {

    }

}