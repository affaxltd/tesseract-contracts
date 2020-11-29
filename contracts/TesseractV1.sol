// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/AutoStake.sol";

contract TesseractV1 is Ownable {
    using SafeMath for uint256;

    uint256 private constant ALLOWANCE = uint256(-1);
    uint256 private constant UNIT = 1e18;

    uint256 private _withdrawalFee;
    uint256 private _totalShares;
    uint256 private _lastTotal;
    mapping(address => uint256) private _share;

    IERC20 private _harvestToken;
    AutoStake private _psPool;

    constructor(
        IERC20 harvestToken,
        AutoStake psPool,
        uint256 fee
    ) public {
        _harvestToken = harvestToken;
        _psPool = psPool;
        _withdrawalFee = fee;
    }

    receive() external payable {}

    function transferStake(uint256 amount) public {
        require(
            _harvestToken.allowance(msg.sender, address(this)) == ALLOWANCE,
            "Not allowed to send farm"
        );

        require(
            _harvestToken.balanceOf(msg.sender) >= amount,
            "Not enough farm"
        );

        require(
            _harvestToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        _stake(amount, msg.sender);
    }

    function zapStake(
        IERC20 sellToken,
        address spender,
        address payable swapTarget,
        bytes calldata swapCallData
    ) public payable {
        uint256 amount = _swapToken(
            _harvestToken,
            sellToken,
            spender,
            swapTarget,
            msg.sender,
            msg.value,
            swapCallData
        );
        _stake(amount, msg.sender);
    }

    function exitAll() public {
        exit(_balanceOf(msg.sender));
    }

    function exit(uint256 amount) public {
        uint256 tokens = _exit(amount, msg.sender);
        _harvestToken.transfer(msg.sender, tokens);
    }

    // If for some ungodly reason someone sends ether to the address, I can manually just claim it :P
    function flush() public {
        require(address(this).balance > 0, "Balance cannot be empty");
        msg.sender.transfer(address(this).balance);
    }

    function balanceOf() public view returns (uint256) {
        return _balanceOf(msg.sender);
    }

    function poolBalance() public view returns (uint256) {
        return _psPool.balanceOf(address(this));
    }

    function withdrawalFee() public view returns (uint256) {
        return _withdrawalFee;
    }

    /*
    Even though it seems fee can be as high as 50%, uint256 fee is not comparable straight to %
    1 = 0.01% and 10000 = 100%, so the max fee possible is 0.5%
    */
    function setFee(uint256 fee) public onlyOwner {
        require(fee <= 50);
        _withdrawalFee = fee;
    }

    function _exit(uint256 amount, address behalf) internal returns (uint256) {
        require(_balanceOf(behalf) >= amount, "Not enough balance");

        uint256 shares = amount.mul(_totalShares).mul(UNIT).div(poolBalance());

        require(shares > 0, "No shares in the end");

        uint256 fees = amount.div(
            UNIT.mul(10000).div(UNIT.mul(_withdrawalFee))
        );

        _totalShares = _totalShares.sub(shares);
        _share[behalf] = _share[behalf].sub(shares);
        _psPool.exit();
        _harvestToken.transfer(owner(), fees);
        _psPool.stake(_harvestToken.balanceOf(address(this)));
        return amount - fees;
    }

    function _stake(uint256 amount, address behalf) internal {
        _psPool.exit();
        uint256 shares = amount.mul(_lastTotal).mul(UNIT).div(poolBalance());

        require(shares > 0, "No shares in the end");

        _share[behalf] = _share[behalf].add(shares);
        _totalShares = _totalShares.add(shares);
        _psPool.stake(_harvestToken.balanceOf(address(this)));
        _lastTotal = poolBalance();
    }

    function _swapToken(
        IERC20 buyToken,
        IERC20 sellToken,
        address spender,
        address payable swapTarget,
        address payable behalf,
        uint256 value,
        bytes calldata swapCallData
    ) internal returns (uint256) {
        require(
            sellToken.allowance(behalf, spender) == ALLOWANCE,
            "Not allowed to send token"
        );

        uint256 tokens = buyToken.balanceOf(address(this));
        uint256 initialBalance = address(this).balance;
        (bool success, ) = swapTarget.call{value: value}(swapCallData);

        require(success, "Swap failed");

        _refundFees(initialBalance, behalf);

        tokens = buyToken.balanceOf(address(this)) - tokens;

        require(tokens > 0, "No tokens were bought");

        return tokens;
    }

    function _balanceOf(address who) internal view returns (uint256) {
        return _share[who].mul(poolBalance()).div(_totalShares);
    }

    function _refundFees(uint256 initialBalance, address payable behalf)
        internal
    {
        uint256 etherBalance = address(this).balance - initialBalance;

        if (etherBalance > 0) {
            behalf.transfer(etherBalance);
        }
    }
}
