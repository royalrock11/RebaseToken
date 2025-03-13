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

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Reggie Prince
 * @notice This is going to be a cross chain rebase token that   *incentivises user to deposit into a vault.
 * @notice The interest rate in smart contract can only decrease and the rebase token can only decrease
 * @notice each user will have their own interest rate that is the global interest rate at the time of depositing
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    /*//////////////////////////////////////////////////////////////
                        ERRORS
    //////////////////////////////////////////////////////////////*/

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 s_interestRate, uint256 _newInterestRate);

    /*//////////////////////////////////////////////////////////////
                        STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8; // 10^-8 == 1/ 10^8
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    /*//////////////////////////////////////////////////////////////
                        EVENTS
    //////////////////////////////////////////////////////////////*/

    event InterestRateSet(uint256 _newInterestRate);

    /*
    * @notice Set the interest rate in the contract
    * @param _newInterestRate New interest rate
    * @dev The interest rate can only decrease
    */
    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) AccessControl() {}

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of the user. This is the current number of tokens that have been minted to the user, not including any interest that has accumulated since the last time the user has interacted with the protocol.
     * @param _user The user to get the principle balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint tokens to the user when they deposit in the vault
     * @param _to The user to mint tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn tokens from the user when they withdraw from the vault
     * @param _from The user to burn tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // This removes dust from the user
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    /**
     * @notice Get the current balance of the user including the interest that has accumulated since the last update
     * (principle balance) + some interest that has
     * @return The current balance of the user
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have actually been minted to the user)
        // Multiply the principle balance by the interest that has accumulated since the balance was last updated
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from the user to another user
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful, false otherwise
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from the user to another user
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful, false otherwise
     */
    // function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
    //     _mintAccruedInterest(msg.sender);
    //     _mintAccruedInterest(_recipient);
    //     if (_amount == type(uint256).max) {
    //         _amount = balanceOf(msg.sender);
    //     }
    //     if (balanceOf(_recipient) == 0) {
    //         s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
    //     }
    //     return super.transferFrom(_sender, _recipient, _amount);
    // }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender); // Fix: Use _sender
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender); // Fix: Use _sender
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender]; // Fix: Use _sender
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*
    * @notice Calculate the interest that has accumulated since the last update
    * @param _user The user to calculate the interest accumulated
    * @return The interest that has accumulated since the last update
    */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of linear growth
        // principle amount(1 + (user interest rate * time elapsed))
        // deposit: 10 tokens
        // interest rate: 0.5% per second
        // time since last update: 2 seconds
        // 10 + (10 * 0.5% * 2)
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
    }

    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (1) find their current balance of rebase tokens that have been minted to their user --> principal balance
        // (2) calculate their current balance including any interest --> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the amount of tokens that need to be minted to the user --> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the users last updated timestamp
        s_userLastUpdatedTimeStamp[_user] = block.timestamp;
        // call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /*//////////////////////////////////////////////////////////////
                         GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the interest rate that is set for the contract. Any future depositors will receive this interest rate
     * @return The interest rate in the contract
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate in the contract for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
