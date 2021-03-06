pragma solidity ^0.4.17;

import './token/StandardToken.sol';
import './ownership/Ownable.sol';
import './math/SafeMath.sol';

contract HotokenReservation is StandardToken, Ownable {

    using SafeMath for uint256;

    // Constants
    string public constant name = "ReservedHotoken";
    string public constant symbol = "RHTKN";
    uint8 public constant decimals = 18;
    uint256 public constant INITIAL_SUPPLY = 3000000000 * (10 ** uint256(decimals));
    uint256 public constant HTKN_PER_USD = 10;

    // Struct
    struct Ledger {
        uint whenRecorded;
        string currency;
        uint currencyAmount;
        uint usdCentAmount;
        uint usdCentRate;
        uint discountRateIndex;
        uint tokenQuantity;
    }

    struct Whitelist {
        address buyer;
        uint exists;
    }

    // Properties
    uint256 public tokenSold;
    bool    public pause = true;
    uint256 public minimumPurchase;
    bool    public saleFinished = false;
    uint256 public minimumSold;
    uint256 public soldAmount;
    uint256 public refundAmount;
    uint256 public ethConversionToUSDCentsRate;

    // Enum
    enum DiscountRate {ZERO, TWENTY_FIVE, FOURTY_FIVE, SIXTY_FIVE}
    DiscountRate discountRate;

    // Mapping
    mapping(address=>uint) public whitelist;
    mapping(address=>Ledger[]) public ledgerMap;
    mapping(address=>string) public claimTokenMap;
    mapping(address=>uint256) public ethAmount;
    mapping(address=>uint256) public directEthTokens;
    mapping(uint=>uint) public discountRateToTokenPrice;


    // Events
    /**
    * event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event Burn(address indexed burner, uint256 value);
    event RefundTransfer(address _backer, uint _amount);
    event WithdrawOnlyOwner(address _owner, uint _amount);
    event AddToLedger(uint whenRecorded, string currency, uint currencyAmount, uint usdCentAmount, uint usdCentRate, uint discountRateIndex, uint tokenQuantity);

    // Modifiers
    modifier validDestination(address _to) {
        require(_to != address(0x0));
        require(_to != owner);
        _;
    }

    modifier onlyWhenNotPaused() {
        require(!pause);
        _;
    }

    modifier onlySaleIsNotFinished() {
        require(!saleFinished);
        _;
    }

    function HotokenReservation() public {
        totalSupply = INITIAL_SUPPLY;
        balances[msg.sender] = INITIAL_SUPPLY;

        tokenSold = 0;
        discountRate = DiscountRate.SIXTY_FIVE;
        discountRateToTokenPrice[uint(DiscountRate.SIXTY_FIVE)] = 35 * (10 ** uint(15)); // $0.035
        discountRateToTokenPrice[uint(DiscountRate.FOURTY_FIVE)] = 55 * (10 ** uint(15)); // $0.055
        discountRateToTokenPrice[uint(DiscountRate.TWENTY_FIVE)] = 75 * (10 ** uint(15)); // $0.075
        discountRateToTokenPrice[uint(DiscountRate.ZERO)] = 1 * (10 ** uint(17)); // $0.1

        minimumPurchase = 300 * (10 ** uint(decimals)); // $300
        minimumSold = 2 * (10 ** uint(6)) * (10 ** uint(decimals));

        soldAmount = 0;
        refundAmount = 0;
    }

    // fallback function can be used to buy tokens
    function () external payable onlyWhenNotPaused {
        buyTokens(msg.sender);
    }

    function buyTokens(address beneficiary) public payable onlyWhenNotPaused {
        require(beneficiary != address(0));
        require(owner != beneficiary);
        require(whitelist[beneficiary] == 1);

        uint256 amount = msg.value; /* wei */
        uint256 usd = toUsd(amount); /* $1e-18 */

        uint _usdCentRate = ethConversionToUSDCentsRate;
        uint _discountRateIndex = uint(discountRate);

        uint256 toBuyTokens = usdToTokens(usd);
        uint256 updatedSoldTokens = tokenSold.add(toBuyTokens);

        bool exists = ledgerMap[msg.sender].length > 0;

        if ((usd >= minimumPurchase) || exists) {
            require(updatedSoldTokens <= INITIAL_SUPPLY);
            // Update sold token
            tokenSold = updatedSoldTokens;

            // transfer token to purchaser
            uint currentBalance = balances[beneficiary];
            balances[beneficiary] = currentBalance.add(toBuyTokens);

            // decrease balance of owner
            balances[owner] = balances[owner].sub(toBuyTokens);

            // update sold Amount
            soldAmount = soldAmount.add(usd);

            // track ether and tokens from beneficiary
            ethAmount[beneficiary] = ethAmount[beneficiary].add(amount);
            directEthTokens[beneficiary] = directEthTokens[beneficiary].add(toBuyTokens);

            TokenPurchase(msg.sender, beneficiary, amount, toBuyTokens);
            addToLedgerAuto(beneficiary, "ETH", amount, usd, _usdCentRate, _discountRateIndex, toBuyTokens);
        } else {
            revert();
        }
    }

    // Whitelist manipulate function
    function addToWhitelist(address _newAddress) public onlyOwner {
        whitelist[_newAddress] = 1;
    }

    function addManyToWhitelist(address[] _newAddresses) public onlyOwner {
        for (uint i = 0; i < _newAddresses.length; i++) {
            whitelist[_newAddresses[i]] = 1;
        }
    }

    function removeFromWhiteList(address _address) public onlyOwner {
        whitelist[_address] = 0;
    }

    function removeManyFromWhitelist(address[] _addresses) public onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            whitelist[_addresses[i]] = 0;
        }
    }

    // TODO update doc comment
    /**
    * add information of buyer to ledger
    * @param _address address of buyer
    * @param _currency currency that buyer spent
    * @param _currencyAmount amount of the currency (USD in Cent, BTC in one-ten-thousandth BTC. 0.0001)
    * @param _usdCentAmount amount in Cent
    * @param _usdCentRate conversion rate of the currency in Cents
    * @param _discountRateIndex index of discount rate (0=0%, 1=25%, 2=45%, 3=65%)
    * @param _tokens amount of tokens [need to be in wei amount (with multiply by 10 pow 18)]
    */
    function addToLedgerManual(
      address _address, string _currency, uint _currencyAmount,
      uint _usdCentAmount, uint _usdCentRate, uint _discountRateIndex,
      uint _tokens) public onlyOwner {
        // need to check amount in case that currency is not ETH
        // check tokens more than supply or not
        uint _whenRecorded = now;
        uint256 updatedSoldTokens = tokenSold.add(_tokens);

        require(_address != owner);
        require(whitelist[_address] == 1);
        require(_usdCentRate > 0);
        require(updatedSoldTokens <= INITIAL_SUPPLY);

        // update sold Amount
        soldAmount = soldAmount.add(_usdCentAmount.mul(10 ** uint(decimals-2)));

        // increase tokenSold
        tokenSold = tokenSold.add(_tokens);

        // update balance of buyer
        uint currentBalance = balances[_address];
        balances[_address] = currentBalance.add(_tokens);
        balances[msg.sender] = balances[msg.sender].sub(_tokens);

        AddToLedger(_whenRecorded, _currency, _currencyAmount, _usdCentAmount, _usdCentRate, _discountRateIndex, _tokens);
        ledgerMap[_address].push(
            Ledger(
                _whenRecorded, _currency, _currencyAmount, _usdCentAmount, _usdCentRate, _discountRateIndex, _tokens
            )
        );
    }

    function addToLedgerAuto(address _address, string _currency, uint _ethAmount,
        uint _usdCentAmount, uint _usdCentRate, uint _discountRateIndex,
        uint _tokens) internal {

        require(_address != owner);
        require(_usdCentRate > 0);

        uint _whenRecorded = now;

        AddToLedger(_whenRecorded, _currency, _ethAmount, _usdCentAmount, _usdCentRate, _discountRateIndex, _tokens);
        ledgerMap[_address].push(
            Ledger(
                _whenRecorded, _currency, _ethAmount, _usdCentAmount, _usdCentRate, _discountRateIndex, _tokens
            )
        );
    }

    /**
    * set pause state for preventing sale from buyers
    * @param _pause boolean
    */
    function setPause(bool _pause) public onlyOwner {
        pause = _pause;
    }

    /**
    * set discount rate via contract owner
    * @param _rate_index discount rate [0, 1, 2, 3]
    */
    function setDiscountRate(uint _rate_index) public onlyOwner {
        require(uint(DiscountRate.SIXTY_FIVE) >= _rate_index);
        discountRate = DiscountRate(_rate_index);
    }

    function getDiscountRate() public view returns (uint) {
        uint256 _discountRate = uint(discountRate);
        if (_discountRate == 0) {
            return _discountRate;
        }
        return _discountRate.mul(uint(20)).add(uint(5));
    }

    /**
    * To set conversion rate from supported currencies to $e-18
    * @param _usdCentsPer conversion rate in cent; how many cent for 1 currency unit (int)
    */
    function setConversionToUSDCentsRate(uint _usdCentsPer) public onlyOwner {
        ethConversionToUSDCentsRate = _usdCentsPer;
    }

    function toUsd(uint _unit) public view returns (uint) {
      return _unit.mul(ethConversionToUSDCentsRate).mul(10 ** uint(decimals-2)).div(10 ** uint(decimals));
    }

    function usdToTokens(uint _usd) public view returns (uint) {
      uint price = discountRateToTokenPrice[uint(discountRate)];
      return _usd.mul(10 ** uint(decimals)).div(price);
    }

    /**
    * To set minimum purchase
    * @param _minUsd in usd (int)
    */
    function setMinimumPurchase(uint _minUsd) public onlyOwner {
        minimumPurchase = _minUsd.mul(10 ** uint(decimals));
    }

    /**
    * Claim Tokens
    * @param _address address for sending token to
    */
    function claimTokens(string _address) public onlyWhenNotPaused {
        require(saleFinished);
        require(soldAmount >= minimumSold);
        require(msg.sender != owner);
        require(whitelist[msg.sender] == 1);
        require(ledgerMap[msg.sender].length > 0);
        claimTokenMap[msg.sender] = _address;
    }

    function transfer(address _to, uint256 _value) public onlyOwner validDestination(_to) returns (bool) {
        return super.transfer(_to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) public onlyOwner validDestination(_to) returns (bool) {
        return super.transferFrom(_from, _to, _value);
    }

    /**
    * Set the minimum sold in usd currency.
    * @param _minimumSold minimumSold
    */
    function setMinimumSold(uint _minimumSold) public onlyOwner {
        minimumSold = _minimumSold.mul(10 ** uint(decimals));
    }

    /**
    * Set the sale finish flag
    * @param _saleFinished sale finished
    */
    function setSaleFinished(bool _saleFinished) public onlyOwner {
        saleFinished = _saleFinished;
    }

    /**
    * This function permits anybody to withdraw the funds they have
    * contributed if and only if the deadline has passed and the
    * funding goal was not reached.
    */
    function refund() public onlyWhenNotPaused {
        require(saleFinished);
        require(soldAmount < minimumSold);
        require(msg.sender != owner);
        require(whitelist[msg.sender] == 1);
        require(ledgerMap[msg.sender].length > 0);

        uint amount = ethAmount[msg.sender];
        ethAmount[msg.sender] = 0;
        if (amount > 0) {
            // TODO remove only directed ETH tokens
            uint toDeductTokens = directEthTokens[msg.sender];
            balances[msg.sender] = balances[msg.sender].sub(toDeductTokens);
            directEthTokens[msg.sender] = 0;
            msg.sender.transfer(amount);
            RefundTransfer(msg.sender, amount);
            refundAmount = refundAmount.add(amount);
        }
    }

    /**
    * withdraw ether from contract for owner
    */
    function withDrawOnlyOwner() public onlyOwner {
        require(saleFinished);
        require(soldAmount >= minimumSold);
        uint balanceToSend = this.balance;
        msg.sender.transfer(balanceToSend);
        WithdrawOnlyOwner(msg.sender, balanceToSend);
    }

    /**
    * @dev Burns a specific amount of tokens.
    */
    function burn() public onlyOwner {
        require(saleFinished);
        uint valueToBurn = totalSupply.sub(tokenSold);

        address burner = msg.sender;
        balances[burner] = balances[burner].sub(valueToBurn);
        totalSupply = totalSupply.sub(valueToBurn);
        Burn(burner, valueToBurn);
    }

    // Kill the contract
    function kill() public onlyOwner {
        require(saleFinished);
        require(this.balance == 0);
        selfdestruct(owner);
    }
}
