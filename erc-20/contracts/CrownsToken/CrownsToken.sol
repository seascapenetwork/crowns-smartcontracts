// contracts/Crowns.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.6.7;

import "./../../../../openzeppelin/contracts/access/Ownable.sol";
import "./../../../../openzeppelin/contracts/GSN/Context.sol";
import "./../../../../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../../../../openzeppelin/contracts/math/SafeMath.sol";
import "./../../../../openzeppelin/contracts/utils/Address.sol";

/// @title Official token of Blocklords and the Seascape ecosystem.
/// @author Medet Ahmetson
/// @notice Crowns (CWS) is an ERC-20 token with a payWave feature.
/// Rebasing is a distribution of spent tokens among all current token holders.
/// In order to appear in balance, payWaved tokens need to be claimed by users by triggering transaction with the ERC-20 contract.
/// @dev Implementation of the {IERC20} interface.
contract CrownsToken is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    struct Account {
        uint256 balance;
        uint256 lastPayWave;
    }

    mapping (address => Account) private _accounts;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;

    uint256 private constant MIN_SPEND = 10 ** 6;
    uint256 private constant SCALER = 10 ** 18;


    /// @notice Total amount of tokens that have yet to be transferred to token holders as part of a payWave.
    /// @dev Used Variable tracking unclaimed payWave token amounts.
    uint256 public unclaimedPayWave = 0;
    /// @notice Amount of tokens spent by users that have not been payWaved yet.
    /// @dev Calling the payWave function will move the amount to {totalPayWave}
    uint256 public unconfirmedPayWave = 0;
    /// @notice Total amount of tokens that were payWaved overall.
    /// @dev Total aggregate payWave amount that is always increasing.
    uint256 public totalPayWave = 0;


    /**
     * @dev Emitted when `spent` tokens are moved `unconfirmedPayWave` to `totalPayWave`.
     */
    event PayWave(
        uint256 spent,
        uint256 totalPayWave
    );



    /**
     * @dev Sets the {name} and {symbol} of token.
     * Initializes {decimals} with a default value of 18.
     * Mints all tokens.
     * Transfers ownership to another account. So, the token creator will not be counted as an owner.
     */
    constructor () public {
        _name = "";
        _symbol = "CWS";
        _decimals = 18;

        // Grant the minter roles to a specified account
        address inGameAirdropper     = 0x2F8EAE5771E6100f27D6c382D37d990B4F59b3a2;
        address rechargeDexManager   = 0xD70279EF7B2C83F8D6157219F832F1B00525DDcF;
        address teamManager          = 0xc9603191b6933C97E7e66F5F68697Bb879f47e56;
        address investManager        = 0x84EdD4C1ebc80243c0e8B5E6119c177838E35F0E;
        address communityManager     = 0xB257aBb3A2F47eDF8f8E9CEb71D93A90E1050323;
        address newOwner             = msg.sender;

        // 3 million tokens
        uint256 inGameAirdrop        = 5e6 * SCALER;
        uint256 rechargeDex          = 1e6 * SCALER;
        // 1 million tokens
        uint256 teamAllocation       = 1e6 * SCALER;
        uint256 investment           = 1e6 * SCALER;
        // 750,000 tokens
        uint256 communityBounty      = 500000 * SCALER;
        // 1,25 million tokens
        uint256 inGameReserve        = 1500000 * SCALER; // reserve for the next 5 years.

        _mint(inGameAirdropper,      inGameAirdrop);
        _mint(rechargeDexManager,    rechargeDex);
        _mint(teamManager,           teamAllocation);
        _mint(investManager,         investment);
        _mint(communityManager,      communityBounty);
        _mint(newOwner,              inGameReserve);

        transferOwnership(newOwner);
   }

    /**
     * @notice Return amount of tokens that {account} gets during payWave
     * @dev Used both internally and externally to calculate the payWave amount
     * @param account is an address of token holder to calculate for
     * @return amount of tokens that player could get
     */
    function payWaveOwing (address account) public view returns(uint256) {
        Account memory _account = _accounts[account];

        uint256 newPayWave = totalPayWave.sub(_account.lastPayWave);
        uint256 proportion = _account.balance.mul(newPayWave);

        // The payWave is not a part of total supply, since it was moved out of balances
        uint256 supply = _totalSupply.sub(newPayWave);

        // payWave owed proportional to current balance of the account.
        // The decimal factor is used to avoid floating issue.
        uint256 payWave = proportion.mul(SCALER).div(supply).div(SCALER);

        return payWave;
    }

    /**
     * @dev Called before any edit of {account} balance.
     * Modifier moves the belonging payWave amount to its balance.
     * @param account is an address of Token holder.
     */
    modifier updateAccount(address account) {
        uint256 owing = payWaveOwing(account);
        _accounts[account].lastPayWave = totalPayWave;

        if (owing > 0) {
            _accounts[account].balance    = _accounts[account].balance.add(owing);
            unclaimedPayWave     = unclaimedPayWave.sub(owing);

            emit Transfer(
                address(0),
                account,
                owing
            );
        }

        _;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _getBalance(account);
    }

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal updateAccount(sender) updateAccount(recipient) virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Can not send 0 token");
        require(_getBalance(sender) >= amount, "ERC20: Not enough token to send");

        _beforeTokenTransfer(sender, recipient, amount);

        _accounts[sender].balance =  _accounts[sender].balance.sub(amount);
        _accounts[recipient].balance = _accounts[recipient].balance.add(amount);

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _accounts[account].balance = _accounts[account].balance.add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Moves `amount` tokens from `account` to {unconfirmedPayWave} without reducing the
     * total supply. Will be payWaved among token holders.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal updateAccount(account) virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        require(_getBalance(account) >= amount, "ERC20: Not enough token to burn");

        _beforeTokenTransfer(account, address(0), amount);

        _accounts[account].balance = _accounts[account].balance.sub(amount);

        unconfirmedPayWave = unconfirmedPayWave.add(amount);

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }

    /**
     * @notice Spend some token from caller's balance in the game.
     * @dev Moves `amount` of token from caller to `unconfirmedPayWave`.
     * @param amount Amount of token used to spend
     */
    function spend(uint256 amount) public returns(bool) {
        require(amount > MIN_SPEND, "Crowns: trying to spend less than expected");
        require(_getBalance(msg.sender) >= amount, "Crowns: Not enough balance");

        _burn(msg.sender, amount);

	return true;
    }

    function spendFrom(address sender, uint256 amount) public returns(bool) {
	require(amount > MIN_SPEND, "Crowns: trying to spend less than expected");
	require(_getBalance(sender) >= amount, "Crowns: not enough balance");

	_burn(sender, amount);
	_approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));

	return true;
    }

    /**
     * @notice Return the payWave amount, when `account` balance was updated.
     */
    function getLastPayWave(address account) public view returns (uint256) {
        return _accounts[account].lastPayWave;
    }

    /**
     * @dev Returns actual balance of account as a sum of owned divends and current balance.
     * @param account Address of Token holder.
     * @return Token amount
     */
    function _getBalance(address account) private view returns (uint256) {
        uint256 balance = _accounts[account].balance;
    	if (balance == 0) {
    		return 0;
    	}
    	uint256 owing = payWaveOwing(account);

    	return balance.add(owing);
    }

    /**
     * @notice Rebasing is a unique feature of Crowns (CWS) token. It redistributes tokens spenth within game among all token holders.
     * @dev Moves tokens from {unconfirmedPayWave} to {totalPayWave}.
     * Any account balance related functions will use {totalPayWave} to calculate the dividend shares for each account.
     *
     * Emits a {payWave} event.
     */
    function payWave() public onlyOwner() returns (bool) {
    	totalPayWave = totalPayWave.add(unconfirmedPayWave);
    	unclaimedPayWave = unclaimedPayWave.add(unconfirmedPayWave);
    	unconfirmedPayWave = 0;

        emit PayWave (
            unconfirmedPayWave,
            totalPayWave
        );

        return true;
    }
}
