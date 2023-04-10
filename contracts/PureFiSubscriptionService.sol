pragma solidity >=0.8.0;

import "../openzeppelin-contracts-upgradeable-master/contracts/access/AccessControlUpgradeable.sol";
import "../openzeppelin-contracts-upgradeable-master/contracts/token/ERC20/IERC20Upgradeable.sol";
import "../openzeppelin-contracts-upgradeable-master/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./chainlink/contracts/src/v0.8/AutomationCompatible.sol";

import "./tokenbuyer/ITokenBuyer.sol";
import "./interfaces/IProfitDistributor.sol";

contract PureFiSubscriptionService is AccessControlUpgradeable, AutomationCompatible {

    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant P100 = 100; //100% denominator
    uint256 private constant MONTH = 30*24*60*60; //30 days in seconds
    uint256 private constant YEAR = 12 * MONTH; 
 
    IERC20Upgradeable private ufiToken;
    ITokenBuyer private tokenBuyer;
    address private profitCollectionAddress;

    // uint256 collectedProfit; //amount of tokens collected as a profit from subsciptions selling

    //0x - 04 bytes //number of users
    //0x - 12 bytes //sigma dep_i
    //0x - 16 bytes //sigma t_i*dep_i
    uint256 private userstat; 
    
    mapping (uint8 => Tier) tiers;
    mapping (address => UserSubscription) userSubscriptions;
    //2000004
    uint256 private unrealizedProfit; //profit gained when unsubscribe triggered that is not immediately distributed
    uint256 private lastProfitToDate; 
    uint64 private lastProfitDistributedTimestamp;// last profit distribution date
    uint8 private profitDistributionPart;//percents / P100
    uint24 private profitDistributionInterval;//seconds
    address private profitDistributionAddress; // distributor contract address

    //2000009
    bool public isProfitDistributionPaused; // true - is paused; false - vice versa

    struct Tier{
        uint8 isactive; //1 - active, 0 - non acvite (can't subscribe)
        uint48 subscriptionDuration; //subscriptionDuration = token lockup time in seconds.
        uint128 priceInUSD; // tier price in USD 
        uint8 burnRatePercent; // burn rate in percents with 0 decimals (100% = P100)
        uint16 kycIncluded;
        uint48 amlIncluded;
    }

    struct UserSubscription{
        uint8 tier;
        uint64 dateSubscribed;
        uint128 tokensDeposited; //tokens tokensDeposited
        uint48 userdata;//storage reserve for future 
    }

    event Subscribed(address indexed subscriber, uint8 tier, uint64 dateSubscribed, uint256 UFILocked);
    event Unsubscribed(address indexed subscriber, uint8 tier, uint64 dateUnsubscribed, uint256 ufiBurned);
    event ProfitDistributed(address indexed profitCollector, uint256 amount);

    modifier profitDistributionIsActive(){
        require( isProfitDistributionPaused == false, "PureFiSubscriptionService : ProfitDistribution is disabled" );
        _;
    }

    /**
    Changelog:
    1000001 -> 1000002
    1. fixed issue with getUserData();
    1000002 -> 1000003
    1. changed subscription time calculation to round up to nearest month. I.e. minimum subscription time = 1 month;
    2000004 -> 2000005
    1. fix using busdToUfi function
    2. fix formula in _collectProfit(), _estimateProfit
    2000005->2000006
    1. Make contract keeper compatible
    2000008 -> 2000009
    1. Add flag for automation (Chainlink) functionality
        
    */
    function version() public pure returns(uint32){
        // 000.000.000 - Major.minor.internal
        return 2000009;
    }

    function initialize(address _admin, address _ufi, address _tokenBuyer, address _profitCollectionAddress) public initializer{
        __AccessControl_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        // lockService = PureFiLockService(_lock);
        ufiToken = IERC20Upgradeable(_ufi);
        tokenBuyer = ITokenBuyer(_tokenBuyer);
        profitCollectionAddress = _profitCollectionAddress;
    }

    function setTokenBuyer(address _tokenBuyer) external onlyRole(DEFAULT_ADMIN_ROLE){
        tokenBuyer = ITokenBuyer(_tokenBuyer);
    }

    function setProfitCollectionAddress(address _profitCollectionAddress) external onlyRole(DEFAULT_ADMIN_ROLE){
        profitCollectionAddress = _profitCollectionAddress;
    }

    function setProfitDistributionParams(address _profitDistributionContract, uint8 _part, uint24 _interval) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(_part <= P100,"Incorrect _part param");
        require(_interval <= MONTH, "Max distribution interval is 1 month");
        profitDistributionPart = _part;
        profitDistributionAddress = _profitDistributionContract;
        profitDistributionInterval = _interval;
    }

    function setTierData(
        uint8 _tierID,
        uint48 _subscriptionDuration, //subscriptionDuration = token lockup time in seconds.
        uint128 _priceInUSD, // tier price in USD 
        uint8 _burnRatePercent, // burn rate in percents with 2 decimals (100% = 10000)
        uint16 _kycIncluded,
        uint48 _amlIncluded) external onlyRole(DEFAULT_ADMIN_ROLE){
        tiers[_tierID] = Tier(1, _subscriptionDuration,_priceInUSD,_burnRatePercent,_kycIncluded,_amlIncluded);
    }

    function setTierIsActive(uint8 _tierID, uint8 _isActive) external onlyRole(DEFAULT_ADMIN_ROLE){
        tiers[_tierID].isactive = _isActive;
    }

    function pauseProfitDistribution() external onlyRole(DEFAULT_ADMIN_ROLE){
        isProfitDistributionPaused = true;
    }

    function unpauseProfitDistribution() external onlyRole(DEFAULT_ADMIN_ROLE){
        isProfitDistributionPaused = false;
    }



    function distributeProfit() external {
        _distributeProfit();
    } 

    function _distributeProfit() internal profitDistributionIsActive{
        uint256 totalTokensToDistribute = _collectProfit();
        uint256 tokensToDistribute = totalTokensToDistribute * profitDistributionPart / P100;
        ufiToken.transfer(profitDistributionAddress, tokensToDistribute);
        ufiToken.transfer(profitCollectionAddress, totalTokensToDistribute - tokensToDistribute);
        emit ProfitDistributed(profitCollectionAddress, totalTokensToDistribute - tokensToDistribute);
        emit ProfitDistributed(profitDistributionAddress, tokensToDistribute);
        IProfitDistributor(profitDistributionAddress).setDistributionReadinessFlag();
    }

    function subscribe(uint8 _tier) external payable {
       _subscribe(_tier, msg.sender);
    }
    
    function subscribeFor(uint8 _tier, address _subscriber) external payable {
       _subscribe(_tier, _subscriber);
    }

    function unsubscribe() external payable {
        uint8 userSubscriptionTier = userSubscriptions[msg.sender].tier;
        require(userSubscriptionTier > 0, "No subscription found");
        uint256 timeSubscribed = block.timestamp - userSubscriptions[msg.sender].dateSubscribed;
        // round timeSubscribed up to month
        timeSubscribed = (1 + timeSubscribed / MONTH) * MONTH;
        // for expired subscriptions set subscribed time to initial tier duration.
        if (timeSubscribed > tiers[userSubscriptionTier].subscriptionDuration)
            timeSubscribed = tiers[userSubscriptionTier].subscriptionDuration;

        uint256 totalProfit =  userSubscriptions[msg.sender].tokensDeposited * tiers[userSubscriptionTier].burnRatePercent / P100;
        uint256 actualProfit = totalProfit * timeSubscribed  / tiers[userSubscriptionTier].subscriptionDuration; 
        uint256 alreadyCollectedProfit = (lastProfitDistributedTimestamp > 0) ? (totalProfit * (lastProfitDistributedTimestamp - userSubscriptions[msg.sender].dateSubscribed) / YEAR) : 0;        

        if(actualProfit > alreadyCollectedProfit){
            unrealizedProfit += actualProfit - alreadyCollectedProfit;
        }
        ufiToken.safeTransfer(msg.sender, userSubscriptions[msg.sender].tokensDeposited - actualProfit);
        removeUser(userSubscriptions[msg.sender].dateSubscribed, totalProfit);
        // remove the part of the lastProfitToDate that belongs to this user
        if(lastProfitToDate > userSubscriptions[msg.sender].dateSubscribed)
            lastProfitToDate -= alreadyCollectedProfit;
        delete userSubscriptions[msg.sender];
        emit Unsubscribed(msg.sender, userSubscriptionTier, uint64(block.timestamp), actualProfit);
    }

    /**
    returns:
    0: amount of UFI to be on a balance for subscription
    1: amount of ETH(BNB) to set as a transaction value for subscription to be successful
    2: amount of UFI that will be locked when subscription applied
    */
    function estimateSubscriptionPrice(address _holder, uint8 _tier) external view returns (uint256, uint256, uint256){
        require(tiers[_tier].priceInUSD > 0, 'Invalid tier provided');
        require(tiers[_tier].isactive > 0, "Tier is not active. Can't subscribe");

        uint256 tokensLeftFromCurrentSubscription = 0;
        //check for existing subscription
        uint8 userSubscriptionTier = userSubscriptions[_holder].tier;
        
        if(userSubscriptionTier > 0){
            uint256 timeSubscribed = block.timestamp - userSubscriptions[_holder].dateSubscribed;
            // round timeSubscribed up to month
            timeSubscribed = (1 + timeSubscribed / MONTH) * MONTH;
            // for expired subscriptions set subscribed time to initial tier duration.
            if (timeSubscribed > tiers[userSubscriptionTier].subscriptionDuration)
                timeSubscribed = tiers[userSubscriptionTier].subscriptionDuration;
            uint256 unrealizedProfitFromCurrentSubscription = userSubscriptions[_holder].tokensDeposited * timeSubscribed * tiers[userSubscriptionTier].burnRatePercent / (tiers[userSubscriptionTier].subscriptionDuration * P100); 
            tokensLeftFromCurrentSubscription = userSubscriptions[_holder].tokensDeposited - unrealizedProfitFromCurrentSubscription;
        }
        //subscripbe to the _tier
        (uint newSubscriptionPriceInWBNB, uint256 newSubscriptionPriceInUFI) = tokenBuyer.busdToUFI(tiers[_tier].priceInUSD);
        uint256 userBalanceUFI = ufiToken.balanceOf(_holder);


        if(tokensLeftFromCurrentSubscription >= newSubscriptionPriceInUFI){
            //this is the case when user subsribes to lower package and remaining tokens are more then enough
            //=> refunding tokens back to user
            return (0, 0, newSubscriptionPriceInUFI);
        }
        else {
            //this is the case when remaining user tokens on the contract is not enough for the new subscription 
            if(newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription > userBalanceUFI){
                uint256 ufiTokenToBuy = newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription - userBalanceUFI + 1;
                uint256 ethToSend = newSubscriptionPriceInWBNB * ufiTokenToBuy * 1001 / 1000 / newSubscriptionPriceInUFI;
                return (newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription, ethToSend, newSubscriptionPriceInUFI);
            } else {
                return (newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription, 0, newSubscriptionPriceInUFI);
            }

        }
    }

    /**
    returns: 
        0: subscription tier
        1: date subscribed
        2: date subscription expires
        3: userdata
        4: locked tokens amount
     */
    function getUserData(address _user) external view returns (uint8, uint64, uint64, uint184, uint256) {
        return (userSubscriptions[_user].tier,
                userSubscriptions[_user].dateSubscribed,
                userSubscriptions[_user].dateSubscribed + ((userSubscriptions[_user].tier > 0)?tiers[userSubscriptions[_user].tier].subscriptionDuration:0),
                userSubscriptions[_user].userdata,
                userSubscriptions[_user].tokensDeposited);
        
    }

    /**
    returns: 
        0: subscription Duration
        1: price in USD
        2: burn rate percent
        3: kyc Included
        4: aml Included
        5: is active flag
     */
    function getTierData(uint8 _tier) external view returns(uint48, uint128, uint8, uint16, uint48, uint8){
        return (tiers[_tier].subscriptionDuration,
                tiers[_tier].priceInUSD,
                tiers[_tier].burnRatePercent,
                tiers[_tier].kycIncluded,
                tiers[_tier].amlIncluded,
                tiers[_tier].isactive
                );
    }

    function getProfitDistributionData() external view returns (address, address, uint8, uint24){
        return (profitCollectionAddress, profitDistributionAddress, profitDistributionPart, profitDistributionInterval);
    }

    function getProfitCalculationDetails() external view returns(uint256, uint256, uint256, uint64){
        return (_estimateProfit(), unrealizedProfit, lastProfitToDate, lastProfitDistributedTimestamp);
    }

    function estimateProfit() external view returns(uint256){
        return _estimateProfit();
    }

    function getUserStat() external view returns(uint256, uint256, uint256) {
        uint256 usersAmount = (userstat >> 224) & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF; //32
        uint256 sDepi =       (userstat >> 128) & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; //96
        uint256 sTiDepi =     (userstat)        & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //128
        return(usersAmount,sDepi,sTiDepi);
    }

    function addUser(uint256 dateSubscribed, uint256 tokensDeposited) private {
        //0x - 04 bytes //number of users
        //0x - 12 bytes //sigma dep_i
        //0x - 16 bytes //sigma t_i*dep_i
        uint256 usersAmount = (userstat >> 224) & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF; //32
        uint256 sDepi =       (userstat >> 128) & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; //96
        uint256 sTiDepi =     (userstat)        & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //128

        usersAmount += 1;
        sDepi += uint96(tokensDeposited);
        sTiDepi += uint128(tokensDeposited * dateSubscribed);

        uint256 stat = (usersAmount << 224)
                        + ((sDepi & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF) << 128)
                        + (sTiDepi & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        //update user stat
        userstat = stat;
    }

    function removeUser(uint256 dateSubscribed, uint256 tokensDeposited) private {
        //0x - 04 bytes //number of users
        //0x - 12 bytes //sigma dep_i
        //0x - 16 bytes //sigma t_i*dep_i
        uint256 usersAmount = (userstat >> 224) & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF; //32
        uint256 sDepi =       (userstat >> 128) & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; //96
        uint256 sTiDepi =     (userstat)        & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //128

        usersAmount -= 1;
        sDepi -= uint96(tokensDeposited);
        sTiDepi -= uint128(tokensDeposited * dateSubscribed);  
        
        uint256 stat = (usersAmount << 224)
                        + ((sDepi & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF) << 128)
                        + ((sTiDepi & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF));
        // update user stat
        userstat = stat;
    }

    function _subscribe(uint8 _tier, address _subscriber) private {
        require(tiers[_tier].priceInUSD > 0, 'Invalid tier provided');
        require(tiers[_tier].isactive > 0, "Tier is not active. Can't subscribe");

        uint256 tokensLeftFromCurrentSubscription = 0;
        //check for existing subscription
        uint8 userCurrentSubscriptionTier = userSubscriptions[_subscriber].tier;
        if(userCurrentSubscriptionTier > 0){
            uint256 timeSubscribed = block.timestamp - userSubscriptions[_subscriber].dateSubscribed;
            // round timeSubscribed up to month
            timeSubscribed = (1 + timeSubscribed / MONTH) * MONTH;
            // for expired subscriptions set subscribed time to initial tier duration.
            if (timeSubscribed > tiers[userCurrentSubscriptionTier].subscriptionDuration)
                timeSubscribed = tiers[userCurrentSubscriptionTier].subscriptionDuration;
            // uint256 unrealizedProfitFromCurrentSubscription = userSubscriptions[_subscriber].tokensDeposited * timeSubscribed * tiers[userCurrentSubscriptionTier].burnRatePercent / (tiers[userCurrentSubscriptionTier].subscriptionDuration * P100); 
            uint256 totalProfit =  userSubscriptions[_subscriber].tokensDeposited * tiers[userCurrentSubscriptionTier].burnRatePercent / P100;
            uint256 actualProfit = totalProfit * timeSubscribed  / tiers[userCurrentSubscriptionTier].subscriptionDuration; 
            uint256 alreadyCollectedProfit = (lastProfitDistributedTimestamp > 0) ? (totalProfit * (lastProfitDistributedTimestamp - userSubscriptions[_subscriber].dateSubscribed) / YEAR) : 0;        

            if(actualProfit > alreadyCollectedProfit){
                unrealizedProfit += actualProfit - alreadyCollectedProfit;
            }

            tokensLeftFromCurrentSubscription = userSubscriptions[_subscriber].tokensDeposited - actualProfit;
            if(lastProfitToDate > userSubscriptions[_subscriber].dateSubscribed)
                lastProfitToDate -= alreadyCollectedProfit;
            removeUser(userSubscriptions[_subscriber].dateSubscribed, totalProfit);
            delete userSubscriptions[_subscriber];
            emit Unsubscribed(_subscriber, userCurrentSubscriptionTier, uint64(block.timestamp), actualProfit);
        }
        //subscripbe to the _tier
        (uint newSubscriptionPriceInWBNB, uint256 newSubscriptionPriceInUFI) = tokenBuyer.busdToUFI(tiers[_tier].priceInUSD);
        uint256 userBalanceUFI = ufiToken.balanceOf(msg.sender);
        uint256 ethRemaining = msg.value;
        if(tokensLeftFromCurrentSubscription >= newSubscriptionPriceInUFI){
            //this is the case when user subsribes to lower package and remaining tokens are more then enough
            //=> refunding tokens back to user
            ufiToken.safeTransfer(_subscriber, tokensLeftFromCurrentSubscription - newSubscriptionPriceInUFI);
        }
        else {
            //this is the case when remaining user tokens on the contract is not enough for the new subscription 
            if(newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription > userBalanceUFI){
                //this is the case when user doesn't have enough UFI tokens on his/her balance
                //0. take all users UFI tokens
                ufiToken.safeTransferFrom(msg.sender, address(this), userBalanceUFI);
                //not enough UFI balance on users wallet => buy UFI. 
                //1. buy exact UFI amount that user lacks for subscription
                //2. set ethToSend to a 0.1% more then estimated to make sure there will be enough UFI for subscription.
                uint256 ufiTokenToBuy = newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription - userBalanceUFI + 1;
                uint256 ethToSend = newSubscriptionPriceInWBNB * ufiTokenToBuy * 1001 / 1000 / newSubscriptionPriceInUFI;
                require(ethRemaining >= ethToSend, "Not enough msg.value for transaction");
                tokenBuyer.buyExactTokens{value:ethToSend}(ufiTokenToBuy, address(this));
                ethRemaining-=ethToSend;
            } else {
                //this is the case when user has enough tokens on his/her balance
                uint256 ufiToClaim = newSubscriptionPriceInUFI - tokensLeftFromCurrentSubscription;
                ufiToken.safeTransferFrom(msg.sender, address(this), ufiToClaim);
            }

        }
        
        userSubscriptions[_subscriber] = UserSubscription(_tier, uint64(block.timestamp), uint128(newSubscriptionPriceInUFI), 0);
        emit Subscribed(_subscriber, _tier, uint64(block.timestamp), newSubscriptionPriceInUFI);
        addUser(block.timestamp, newSubscriptionPriceInUFI * tiers[_tier].burnRatePercent / P100);
        if(ethRemaining > 0){
            payable(msg.sender).transfer(ethRemaining);
        }
    }

    function _collectProfit() private returns (uint256){
        require(block.timestamp >= lastProfitDistributedTimestamp + profitDistributionInterval, "Can't distribute profit until distribution interval ends");

        uint256 usersAmount = (userstat >> 224) & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF; //32
        uint256 sDepi =       (userstat >> 128) & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; //96
        uint256 sTiDepi =     (userstat)        & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //128
        uint256 dateToProfit = (block.timestamp * sDepi - sTiDepi) / YEAR;

        uint256 lastProfit = lastProfitToDate;
        uint256 unrealized = unrealizedProfit;
        lastProfitDistributedTimestamp = uint64(block.timestamp);
        lastProfitToDate = dateToProfit;
        unrealizedProfit = 0;
        return dateToProfit - lastProfit + unrealized;
    }

    function _estimateProfit() private view returns (uint256){
        uint256 usersAmount = (userstat >> 224) & 0x00000000000000000000000000000000000000000000000000000000FFFFFFFF; //32
        uint256 sDepi =       (userstat >> 128) & 0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; //96
        uint256 sTiDepi =     (userstat)        & 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; //128
        uint256 dateToProfit = (block.timestamp * sDepi - sTiDepi) / YEAR;
        return dateToProfit - lastProfitToDate + unrealizedProfit;
    }
    
    // Keeper compatible functions
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData){
        if( block.timestamp - lastProfitDistributedTimestamp > profitDistributionInterval ){
            upkeepNeeded = true;
        }
    }

    function performUpkeep(bytes calldata performData) external{
        require(block.timestamp - lastProfitDistributedTimestamp > profitDistributionInterval, "Interval not ends");
        _distributeProfit();
    }


}