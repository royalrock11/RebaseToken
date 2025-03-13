// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RebaseToken} from "./RebaseToken.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Vault is ReentrancyGuard {
    // We need to pass the token address to the constructor
    // create a deposit function that mints to the user equal to the amount of eth the user has sent
    // create a redeem function that burns for the user and sends the user eth.
    // Create a way to add rewards to the vault

    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error Vault__RedeemFailed();

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IRebaseToken private immutable i_rebaseToken;

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /*//////////////////////////////////////////////////////////////
                         FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}

    /**
     * @notice Allows users to deposit ETH into vault and mint rebase tokens
     */
    function deposit() external payable {
        // 1. We need to use the amount of ETH the user has sent to mint to the tokens to the user
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Allows users to redeem their rebase tokens for ETH
     * @param _amount The amount of tokens to redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. We need to burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Send the user the some eth
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Get the address of the rebase token
     * @return The address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
