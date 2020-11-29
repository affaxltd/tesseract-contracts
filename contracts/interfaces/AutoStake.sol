// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

// Profit Share Pool interface
interface AutoStake {
    function valuePerShare() external view returns (uint256);

    function unit() external view returns (uint256);

    function stake(uint256 amount) external;

    function exit() external;

    function balanceOf(address who) external view returns (uint256);
}
