// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/// @title An implementation for liquidity-sensitive LMSR market maker in Solidity
/// @author Abdulla Al-Kamil
/// @dev Feel free to make any adjustments to the code

import "./ConditionalTokens.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ABDKMath64x64.sol";
import "./Nash.sol";

contract LsLMSR is IERC1155Receiver, Ownable{

  /**
   * Please note: the contract utilitises the ABDKMath library to allow for
   * mathematical functions such as logarithms and exponents. As such, all the
   * state variables are stored as int128(signed 64.64 bit fixed point number).
   */

  using SafeERC20 for IERC20;

  uint public numOutcomes;
  int128[] private q;
  int128 private b;
  int128 private current_cost;
  int128 private total_shares;
  int128 public initial_subsidy;
  int128 public overround; // Store overround as 64.64 fixed-point
  uint256 public accumulatedOverround; // Track accumulated overround fees in wei

  bytes32 public condition;
  ConditionalTokens private CT;
  address public token;

  bool private init;

  // 64.64 fixed-point representation of e (Euler's number)
  int128 constant E_64x64 = 0x2B7E151628AED2A6; // ≈ 2.718281828459045

  // Dummy variable for redeployment uniqueness
  uint256 public dummyVar = 42;

  event BuyTokenCost(uint256 tokenCost, int128 price_);
  event DebugBalanceBefore(uint256 balance);
  event DebugBalanceAfter(uint256 balance);
  event SplitPositionError(string context, string reason);
  event DebugCollateralization(uint256 userPayment, uint256 outcomeTokens, uint256 contractBalance, uint256 requiredCollateral);
  event DebugMergePositions(uint256 outcomeTokens, uint256 balanceBefore, uint256 balanceAfter, int128 refund);
  event DebugSellAttempt(uint256 userBalance, uint256 requestedAmount, uint256 outcomeTokens, int128 refund);
  event DebugMinting(uint256 outcome, uint256 contractBalance, uint256 neededTokens, bool willMint);

  /**
   * @notice Constructor function for the market maker
   * @param _ct The address for the deployed conditional tokens contract
   * @param _token Which ERC-20 token will be used to purchase and redeem
      outcome tokens for this condition
   */
  constructor(
    address _ct,
    address _token,
    address initialOwner
  ) Ownable(initialOwner) {
    CT = ConditionalTokens(_ct);
    token = _token;
  }

  /**
   * @notice Set up some of the variables for the market maker
   * @param _questionId The question ID (needs to be unique)
   * @param _numOutcomes The number of different outcomes available
   * @param bInput The liquidity parameter b for the LMSR market maker
   * @param _initialSubsidy The initial DAI subsidy to deposit in the contract
   * @param _overround How much 'profit' does the AMM claim? Note that this is
   * represented in bips. Therefore inputting 300 represents 0.30%
   */
  function setup(
    bytes32 _questionId,
    uint _numOutcomes,
    uint bInput,
    uint _initialSubsidy,
    uint _overround
  ) public onlyOwner() {
    require(init == false,'Already init');
    require(_overround > 0,'Cannot have 0 overround');
    // Use the LMSR contract as the oracle for ConditionalTokens
    // Note: _oracle parameter is ignored - LMSR contract is always the oracle
    CT.prepareCondition(address(this), _questionId, _numOutcomes);
    condition = CT.getConditionId(address(this), _questionId, _numOutcomes);

    numOutcomes = _numOutcomes;
    int128 n = ABDKMath.fromUInt(_numOutcomes);
    int128 initial_b = getTokenEth(token, bInput);
    b = initial_b;

    // Transfer the initial subsidy to the contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), _initialSubsidy);

    // Set the initial subsidy in fixed-point format
    initial_subsidy = getTokenEth(token, _initialSubsidy);

    for(uint i=0; i<_numOutcomes; i++) {
      q.push(0); // Start each outcome with zero shares
    }

    init = true;

    total_shares = ABDKMath.mul(initial_subsidy, n);
    current_cost = cost();
    overround = ABDKMath.divu(_overround, 10000);
  }

  function _calculateBuyPrice(
    int128[] memory q_,
    uint256 _outcome,
    int128 _amount,
    int128 total_shares_,
    int128 current_cost_,
    uint numOutcomes_
  ) internal view returns (int128 new_cost, int128 price_, int128 new_total_shares) {
    int128[] memory new_q = new int128[](numOutcomes_);
    for (uint i = 0; i < numOutcomes_; i++) {
        new_q[i] = q_[i];
    }
    new_q[_outcome] = ABDKMath.add(new_q[_outcome], _amount);
    new_total_shares = ABDKMath.add(total_shares_, _amount);
    // Use the contract's b (fixed) instead of recalculating
    int128 used_b = b;

    int128 sum_total;
    for (uint i = 0; i < numOutcomes_; i++) {
        sum_total = ABDKMath.add(sum_total, ABDKMath.exp(ABDKMath.div(new_q[i], used_b)));
    }
    new_cost = ABDKMath.mul(used_b, ABDKMath.ln(sum_total));
    price_ = ABDKMath.sub(new_cost, current_cost_);
  }

  function _mintAndTransferOutcomeTokens(
    uint256 _outcome,
    int128 _amount
  ) internal {
    uint n_outcome_tokens = getTokenWeiUp(token, _amount);
    uint pos = CT.getPositionId(IERC20(token),
        CT.getCollectionId(bytes32(0), condition, 1 << _outcome));

    uint contractBalance = CT.balanceOf(address(this), pos);
    bool willMint = contractBalance < n_outcome_tokens;
    
    if (willMint) {
        // Only mint the difference between what we need and what we have
        uint tokensToMint = n_outcome_tokens - contractBalance;
        IERC20(token).approve(address(CT), tokensToMint);
        CT.splitPosition(IERC20(token), bytes32(0), condition,
            getPositionAndDustPositions(_outcome), tokensToMint);
    }
    CT.safeTransferFrom(address(this), msg.sender, pos, n_outcome_tokens, '');
  }

  function buy(
    uint256 _outcome,
    uint256 _betAmount
  ) public onlyAfterInit returns (uint256 sharesReceived) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_betAmount > 0, "Bet amount must be positive");
    require(CT.payoutDenominator(condition) == 0, 'Market already resolved');

    // 1. Transfer the full bet amount from user to LMSR contract
    require(IERC20(token).transferFrom(msg.sender, address(this), _betAmount), 'Error transferring tokens');
    
    // 2. Apply overround to the bet amount using the set overround value
    // Convert overround from fixed-point to basis points
    uint256 overroundBips = ABDKMath.mulu(overround, 10000);
    uint256 overroundPercentage = 10000 - overroundBips; // e.g., 10000 - 200 = 9800 (98%)
    uint256 betAfterOverround = (_betAmount * overroundPercentage) / 10000;
    uint256 overroundCollected = _betAmount - betAfterOverround;
    
    // Track accumulated overround
    accumulatedOverround += overroundCollected;
    
    // 3. Calculate shares using the reduced bet amount
    uint256 sharesToBuy = calculateSharesFromBetAmount(_outcome, betAfterOverround);
    require(sharesToBuy > 0, "Bet amount too small to buy any shares");

    // 4. Convert shares to fixed-point for state updates
    int128 sharesFixed = getTokenEth(token, sharesToBuy);

    // 5. Update the LMSR state with the actual shares given to user
    q[_outcome] = ABDKMath.add(q[_outcome], sharesFixed);
    total_shares = ABDKMath.add(total_shares, sharesFixed);
    current_cost = cost(); // Recalculate cost with new state

    // 6. Mint and transfer the calculated shares to user
    _mintAndTransferOutcomeTokens(_outcome, sharesFixed);

    return sharesToBuy;
  }

  // getPositionAndDustPositions(1 << _outcome), n_outcome_tokens);

  function getOnes(uint n) internal pure returns (uint count) {
    count = 0;
    while(n!=0) {
      n = n&(n-1);
      count++;
    }
  }

  function withdraw() public onlyAfterInit() onlyOwner() {
    require(CT.payoutDenominator(condition) != 0, 'Market needs to be resolved');
    uint[] memory dust = new uint256[](numOutcomes);
    // uint p = 0;
    for (uint i=0; i<numOutcomes; i++) {
      dust[i] = 1<<i;
    }
    CT.redeemPositions(IERC20(token), bytes32(0), condition, dust);
    IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
  }

  function getPositionAndDustPositions(
    uint _outcome
  ) public view returns (uint256[] memory){
    uint index = (1<<numOutcomes)-1;
    uint inv = (1 << _outcome) ^ index;
    uint[] memory partx = new uint256[](getOnes(inv)+1);
    uint n = 1;
    partx[0] = (1 << _outcome);
    for(uint i=0; i<numOutcomes; i++) {
      if((inv & 1<<i) != 0) {
        partx[n] = 1<<i;
        n++;
      }
    }
    return partx;
  }

  /**
   * @notice View function returning the cost function.
   *  This function returns the cost for this inventory state. It will be able
      to tell you the total amount of collateral spent within the market maker.
      For example, if a pool was seeded with 100 DAI and then a further 20 DAI
      has been spent, this function will return 120 DAI.
   */
  function cost() public view onlyAfterInit() returns (int128) {
    int128 sum_total;
    for(uint i=0; i< numOutcomes; i++) {
      sum_total = ABDKMath.add(sum_total, ABDKMath.exp(ABDKMath.div(q[i], b)));
    }
    return ABDKMath.mul(b, ABDKMath.ln(sum_total));
  }

  /**
   * @notice Calculate exact shares that can be bought with a given DAI amount
   * @param _outcome The outcome to buy shares for
   * @param _betAmount The DAI amount the user wants to spend
   * @return shares The exact number of shares that can be bought
   */
  function calculateSharesFromBetAmount(
    uint256 _outcome,
    uint256 _betAmount
  ) public view onlyAfterInit returns (uint256 shares) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_betAmount > 0, "Bet amount must be positive");

    // Convert bet amount to fixed-point
    int128 betAmountFixed = getTokenEth(token, _betAmount);
    
    // Algebraic solution for x in: betAmount = b * ln(e^((q_outcome + x)/b) + sum_other e^(q_other/b)) - current_cost
    // Rearranging: e^((q_outcome + x)/b) = e^((betAmount + current_cost)/b) - sum_other e^(q_other/b)
    // Then: x = b * ln(e^((betAmount + current_cost)/b) - sum_other e^(q_other/b)) - q_outcome
    
    // Calculate e^((betAmount + current_cost)/b)
    int128 targetCost = ABDKMath.add(betAmountFixed, current_cost);
    int128 expTargetCostOverB = ABDKMath.exp(ABDKMath.div(targetCost, b));
    
    // Calculate sum of e^(q_other/b) for all other outcomes
    int128 sumOtherOutcomes = ABDKMath.fromUInt(0);
    for (uint i = 0; i < numOutcomes; i++) {
      if (i != _outcome) {
        sumOtherOutcomes = ABDKMath.add(sumOtherOutcomes, ABDKMath.exp(ABDKMath.div(q[i], b)));
      }
    }
    
    // Calculate e^((q_outcome + x)/b) = e^((betAmount + current_cost)/b) - sum_other e^(q_other/b)
    int128 expOutcomePlusXOverB = ABDKMath.sub(expTargetCostOverB, sumOtherOutcomes);
    
    // Ensure the result is positive
    require(expOutcomePlusXOverB > ABDKMath.fromUInt(0), "Bet amount too large for current market state");
    
    // Solve for x: x = b * ln(e^((q_outcome + x)/b)) - q_outcome
    int128 x = ABDKMath.sub(
      ABDKMath.mul(b, ABDKMath.ln(expOutcomePlusXOverB)),
      q[_outcome]
    );
    
    // Ensure x is non-negative
    require(x >= ABDKMath.fromUInt(0), "Invalid share calculation");
    
    // Convert back to uint256 and return
    return getTokenWeiDown(token, x);
  }

  /**
   *  This function will tell you the cost (similar to above) after a proposed
      transaction.
   */
  function cost_after_buy(
    uint256 _outcome,
    int128 _amount
  ) public view returns (int128) {
    int128 sum_total;
    int128[] memory newq = new int128[](q.length);
    // Use the contract's fixed b parameter
    int128 used_b = b;

    for(uint j=0; j< numOutcomes; j++) {
      if((_outcome & (1<<j)) != 0) {
        newq[j] = ABDKMath.add(q[j], _amount);
      } else {
        newq[j] = q[j];
      }
    }

    for(uint i=0; i< numOutcomes; i++) {
      sum_total = ABDKMath.add(sum_total,
        ABDKMath.exp(
          ABDKMath.div(newq[i], used_b)
          ));
    }

    return ABDKMath.mul(used_b, ABDKMath.ln(sum_total));
}

  /**
   *  This function tells you how much it will cost to make a particular trade.
      It does this by calculating the difference between the current cost and
      the cost after the transaction.
   */

  function odds(
    uint256 _outcome
  ) public view returns (int128) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    // Calculate numerator: e^(q[_outcome]/b)
    int128 numerator = ABDKMath.exp(ABDKMath.div(q[_outcome], b));
    // Calculate denominator: sum_j e^(q[j]/b)
    int128 denominator;
    for (uint i = 0; i < numOutcomes; i++) {
      denominator = ABDKMath.add(denominator, ABDKMath.exp(ABDKMath.div(q[i], b)));
    }
    // Return probability as 64.64 fixed-point
    return ABDKMath.div(numerator, denominator);
  }
  
  function price(
    uint256 _outcome,
    int128 _amount
  ) public view returns (int128) {
    return cost_after_buy(_outcome, _amount) - current_cost;
  }

  function sellingPrice(
    uint256 _outcome,
    int128 _amount
  ) public view returns (int128) {
    return current_cost - cost_after_buy(_outcome, -_amount);
}

  function getTokenWei(address _token, int128 _amount) public view returns (uint) {
    uint d = ERC20(_token).decimals();
    uint multiplier = 10 ** d;
    require(_amount >= 0, "Amount must be non-negative");
    // Use ABDKMath.mulu for multiplication
    uint result = ABDKMath.mulu(_amount, multiplier);
    // Rounding up: if there's any remainder, add 1
    return result;
}

  function getTokenWeiUp(address _token, int128 _amount) public view returns (uint) {
    uint d = ERC20(_token).decimals();
    uint multiplier = 10 ** d;
    require(_amount >= 0, "Amount must be non-negative");
    // Calculate the product in 256-bit space
    uint result = ABDKMath.mulu(_amount, multiplier);
    // Now check if there is any remainder by doing the division in fixed-point
    // _amount is 64.64, multiplier is integer
    // If (_amount * multiplier) % 1 != 0, round up
    if (ABDKMath.mul(_amount, int128(int256(multiplier))) & 0xFFFFFFFFFFFFFFFF > 0) {
        result += 1;
    }
    return result;
}

  function getTokenWeiDown(address _token, int128 _amount) public view returns (uint) {
    uint d = ERC20(_token).decimals();
    uint multiplier = 10 ** d;
    require(_amount >= 0, "Amount must be non-negative");
    return ABDKMath.mulu(_amount, multiplier); // Default is round down
}

  function getTokenEth(
    address _token,
    uint _amount
  ) public view returns (int128) {
    uint d = ERC20(_token).decimals();
    return ABDKMath.divu(_amount, 10 ** d);
  }

  function onERC1155Received(
    address /* operator */,
    address /* from */,
    uint256 /* id */,
    uint256 /* value */,
    bytes calldata /* data */
  ) external override pure returns(bytes4) {
    return this.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address /* operator */,
    address /* from */,
    uint256[] calldata /* ids */,
    uint256[] calldata /* values */,
    bytes calldata /* data */
  ) external override pure returns(bytes4) {
    return this.onERC1155BatchReceived.selector;
  }

   function supportsInterface(
     bytes4 interfaceId
  ) external override view returns (bool) {}

    modifier onlyAfterInit {
      require(init == true);
      _;
    }

    // Function to generate a question ID from a string
    function generateQuestionId(string memory uniqueString) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(uniqueString));
    }

  
  function _calculateSellRefund(
    int128[] memory q_,
    uint256 _outcome,
    int128 _amount,
    int128 total_shares_,
    int128 current_cost_,
    uint numOutcomes_
) internal view returns (int128 new_cost, int128 refund_, int128 new_total_shares) {
    int128[] memory new_q = new int128[](numOutcomes_);
    for (uint i = 0; i < numOutcomes_; i++) {
        new_q[i] = q_[i];
    }
    new_q[_outcome] = ABDKMath.sub(new_q[_outcome], _amount);
    new_total_shares = ABDKMath.sub(total_shares_, _amount);
    // Use the contract's b (fixed) instead of recalculating
    int128 used_b = b;

    int128 sum_total;
    for (uint i = 0; i < numOutcomes_; i++) {
        sum_total = ABDKMath.add(sum_total, ABDKMath.exp(ABDKMath.div(new_q[i], used_b)));
    }
    new_cost = ABDKMath.mul(used_b, ABDKMath.ln(sum_total));
    refund_ = ABDKMath.sub(current_cost_, new_cost);
}

  /**
   * @notice Calculate the refund amount for selling shares (public wrapper)
   * @param _outcome The outcome to sell shares for
   * @param _amount The number of shares to sell (in wei)
   * @return refund The refund amount in wei
   */
  function calculateSellRefund(
    uint256 _outcome,
    uint256 _amount
  ) public view onlyAfterInit returns (uint256 refund) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    
    // Convert wei amount to fixed-point
    int128 amountFixed = getTokenEth(token, _amount);
    
    // Calculate refund using internal function
    (, int128 refund_, ) = _calculateSellRefund(
        q, _outcome, amountFixed, total_shares, current_cost, numOutcomes
    );
    
    // Convert refund back to wei and return
    return getTokenWeiDown(token, refund_);
  }

  function sell(uint256 _outcome, int128 _amount) public onlyAfterInit returns (int128 refund) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    require(CT.payoutDenominator(condition) == 0, "Market already resolved");
    require(q[_outcome] >= _amount, "Not enough shares to sell");

    // 1. Calculate refund BEFORE updating state
    (int128 new_cost, int128 refund_, int128 new_total_shares) = _calculateSellRefund(
        q, _outcome, _amount, total_shares, current_cost, numOutcomes
    );

    uint n_outcome_tokens = getTokenWeiDown(token, _amount);
    
    // 3. Collect shares from user FIRST
    uint pos = CT.getPositionId(IERC20(token), CT.getCollectionId(bytes32(0), condition, 1 << _outcome));
    
    try CT.safeTransferFrom(msg.sender, address(this), pos, n_outcome_tokens, "") {
        // Success - continue
    } catch Error(string memory reason) {
        emit SplitPositionError("safeTransferFrom failed", reason);
        revert(string(abi.encodePacked("safeTransferFrom failed: ", reason)));
    }

    // 4. Find how many tokens we can actually burn (limited by partner outcome tokens)
    uint[] memory partition = getPositionAndDustPositions(_outcome);
    uint burnableAmount = n_outcome_tokens;
    
    for (uint i = 0; i < partition.length; i++) {
        uint posId = CT.getPositionId(IERC20(token), CT.getCollectionId(bytes32(0), condition, partition[i]));
        uint balance = CT.balanceOf(address(this), posId);
        if (balance < burnableAmount) {
            burnableAmount = balance; // Limit to what we can actually burn
        }
    }
    
    // 5. Burn what we can (this gets us some DAI back)
    if (burnableAmount > 0) {
        CT.mergePositions(IERC20(token), bytes32(0), condition, partition, burnableAmount);
    }

    // 6. Update the inventory and state
    q[_outcome] = ABDKMath.sub(q[_outcome], _amount);
    total_shares = new_total_shares;
    current_cost = new_cost;

    // 7. Pay refund to user (from contract balance + DAI from burning)
    uint token_refund = getTokenWeiDown(token, refund_);
    IERC20(token).safeTransfer(msg.sender, token_refund);

    return refund_;
  }

  function getLiquidityParameter() public view returns (int128) {
    return b;
  }

  function getOutcomeSharesPurchased(uint256 _outcome) public view returns (int128) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    return ABDKMath.sub(q[_outcome], initial_subsidy);
}

  event LiquidityAdded(address indexed user, uint256 amount);

  function addLiquidity(uint _amount) public onlyOwner {
    // 1. Transfer tokens from sender to contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);

    // 2. Convert to 64.64 fixed-point
    int128 subsidy = getTokenEth(token, _amount);

    // 3. Add subsidy to each outcome
    for (uint i = 0; i < numOutcomes; i++) {
        q[i] = ABDKMath.add(q[i], subsidy);
    }

    // 4. Update total_shares
    total_shares = ABDKMath.add(total_shares, ABDKMath.mul(subsidy, ABDKMath.fromUInt(numOutcomes)));

    // 5. Recalculate b
    // b = ABDKMath.mul(total_shares, ABDKMath.fromUInt(1)); // No overround

    // 6. Update current_cost
    current_cost = cost();

    // 7. Emit event
    emit LiquidityAdded(msg.sender, _amount);
}

function getAccumulatedFees() public view returns (uint) {
    return accumulatedOverround;
}

function getContractSurplus() public view returns (uint) {
    uint contractBalance = IERC20(token).balanceOf(address(this));
    uint theoreticalCost = getTokenWei(token, current_cost);
    
    // Check if contract balance is greater than theoretical cost to avoid underflow
    if (contractBalance > theoreticalCost) {
        return contractBalance - theoreticalCost;
    } else {
        return 0; // No surplus if balance is less than or equal to theoretical cost
    }
}

event FeesWithdrawn(address indexed to, uint256 amount);
event OverroundUpdated(uint256 newOverround);
event LiquidityParameterUpdated(uint256 newB, uint256 additionalCapital);

function calculateRequiredCapitalForNewB(uint256 _newBInput) public view returns (uint256 requiredCapital) {
    require(_newBInput > 0, "New b must be greater than 0");
    
    // Convert new b input to fixed-point
    int128 newB = getTokenEth(token, _newBInput);
    
    // Ensure new b is greater than current b
    require(newB > b, "New b must be greater than current b");
    
    // Calculate required additional capital: b * ln(2) - initial_subsidy
    int128 ln2 = ABDKMath.ln(ABDKMath.fromUInt(2)); // ln(2) ≈ 0.693
    int128 newMaxLoss = ABDKMath.mul(newB, ln2);
    int128 requiredAdditionalCapital = ABDKMath.sub(newMaxLoss, initial_subsidy);
    
    // Ensure additional capital is sufficient
    require(requiredAdditionalCapital > ABDKMath.fromUInt(0), "New b must be greater than initial subsidy / ln(2)");
    
    // Convert required capital to wei and return
    return getTokenWeiUp(token, requiredAdditionalCapital);
}

function setOverround(uint256 _newOverround) public onlyOwner {
    require(_newOverround > 0, "Overround must be greater than 0");
    require(_newOverround <= 500, "Overround cannot exceed 5% (500 bips)");
    
    overround = ABDKMath.divu(_newOverround, 10000);
    emit OverroundUpdated(_newOverround);
}

function setLiquidityParameter(uint256 _newBInput, uint256 _additionalCapital) public onlyOwner {
    require(_newBInput > 0, "New b must be greater than 0");
    
    // Convert new b input to fixed-point
    int128 newB = getTokenEth(token, _newBInput);
    
    // Ensure new b is greater than current b
    require(newB > b, "New b must be greater than current b");
    
    // Calculate required additional capital: b * ln(2) - initial_subsidy
    int128 ln2 = ABDKMath.ln(ABDKMath.fromUInt(2)); // ln(2) ≈ 0.693
    int128 newMaxLoss = ABDKMath.mul(newB, ln2);
    int128 requiredAdditionalCapital = ABDKMath.sub(newMaxLoss, initial_subsidy);
    
    // Ensure additional capital is sufficient
    require(requiredAdditionalCapital > ABDKMath.fromUInt(0), "New b must be greater than initial subsidy / ln(2)");
    
    // Convert required capital to wei for comparison
    uint256 requiredCapitalWei = getTokenWeiUp(token, requiredAdditionalCapital);
    require(_additionalCapital >= requiredCapitalWei, "Insufficient additional capital provided");
    
    // Transfer the additional capital from owner to contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), _additionalCapital);
    
    // Update the liquidity parameter
    b = newB;
    
    // Recalculate current cost with new b
    current_cost = cost();
    
    emit LiquidityParameterUpdated(_newBInput, _additionalCapital);
}

function withdrawCollectedOverround(uint256 _amount) public onlyOwner {
    require(accumulatedOverround > 0, "No accumulated overround to withdraw");
    require(_amount > 0, "Amount must be greater than 0");
    require(_amount <= accumulatedOverround, "Amount exceeds accumulated overround");
    require(IERC20(token).balanceOf(address(this)) >= _amount, "Insufficient contract balance");
    
    IERC20(token).safeTransfer(owner(), _amount);
    accumulatedOverround -= _amount; // Reduce accumulated overround by withdrawn amount
    emit FeesWithdrawn(owner(), _amount);
}

function debugFees() public view returns (uint contractBalance, uint theoreticalCost, uint accumulatedOverroundFees, uint availableOverround) {
    contractBalance = IERC20(token).balanceOf(address(this));
    theoreticalCost = getTokenWei(token, current_cost);
    accumulatedOverroundFees = accumulatedOverround;
    availableOverround = getContractSurplus();
}

function getPositionInfo(uint256 _outcome) public view returns (uint256 positionId, uint256 balance) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    bytes32 collectionId = CT.getCollectionId(bytes32(0), condition, 1 << _outcome);
    positionId = CT.getPositionId(IERC20(token), collectionId);
    balance = CT.balanceOf(address(this), positionId);
}

function getPositionIds() public view returns (uint256 positionId0, uint256 positionId1) {
    require(numOutcomes == 2, "This function only works for binary markets");
    
    // Position ID for outcome 0
    bytes32 collectionId0 = CT.getCollectionId(bytes32(0), condition, 1 << 0);
    positionId0 = CT.getPositionId(IERC20(token), collectionId0);
    
    // Position ID for outcome 1
    bytes32 collectionId1 = CT.getCollectionId(bytes32(0), condition, 1 << 1);
    positionId1 = CT.getPositionId(IERC20(token), collectionId1);
}

function getRedeemParameters() public view returns (
    address collateralToken,
    bytes32 parentCollectionId,
    bytes32 conditionId,
    uint[] memory indexSets
) {
    collateralToken = token;
    parentCollectionId = bytes32(0);
    conditionId = condition;
    
    // Create indexSets for all outcomes
    indexSets = new uint[](numOutcomes);
    for (uint i = 0; i < numOutcomes; i++) {
        indexSets[i] = 1 << i;
    }
}

function debugRedemption(address user) public view returns (
    uint payoutDenominator,
    uint[] memory payoutNumerators,
    uint[] memory userBalances,
    uint[] memory expectedPayouts
) {
    payoutDenominator = CT.payoutDenominator(condition);
    payoutNumerators = new uint[](numOutcomes);
    userBalances = new uint[](numOutcomes);
    expectedPayouts = new uint[](numOutcomes);
    
    for (uint i = 0; i < numOutcomes; i++) {
        payoutNumerators[i] = CT.payoutNumerators(condition, i);
        
        // Get user's balance for this outcome
        bytes32 collectionId = CT.getCollectionId(bytes32(0), condition, 1 << i);
        uint positionId = CT.getPositionId(IERC20(token), collectionId);
        userBalances[i] = CT.balanceOf(user, positionId);
        
        // Calculate expected payout
        if (payoutDenominator > 0) {
            expectedPayouts[i] = (userBalances[i] * payoutNumerators[i]) / payoutDenominator;
        }
    }
}

function debugRedeemPositions(address user, uint[] calldata indexSets) public view returns (
    uint totalPayout,
    uint[] memory userBalances,
    uint[] memory payoutNumerators,
    uint payoutDenominator,
    uint outcomeSlotCount
) {
    // Get redemption parameters
    (address collateralToken, bytes32 parentCollectionId, bytes32 conditionId, ) = getRedeemParameters();
    
    // Call the ConditionalTokens debug function
    return CT.debugRedeemPositions(
        IERC20(collateralToken),
        parentCollectionId,
        conditionId,
        indexSets,
        user
    );
}

function freezeMarket(bytes32 _questionId) external onlyOwner {
    require(CT.payoutDenominator(condition) == 0, "Market already resolved");
    require(numOutcomes == 2, "This function only works for binary markets");
    
    // Get current market odds
    int128 prob0 = odds(0);  // Outcome 0 probability
    int128 prob1 = odds(1);  // Outcome 1 probability
    
    // Convert to payout numerators (multiply by 1000 for precision)
    uint payout0 = ABDKMath.mulu(prob0, 1000);
    uint payout1 = ABDKMath.mulu(prob1, 1000);
    
    // Create dynamic array for payouts
    uint[] memory payouts = new uint[](2);
    payouts[0] = payout0;
    payouts[1] = payout1;
    
    // Report freeze resolution with current odds
    CT.reportPayouts(_questionId, payouts);
}

function reportFullPayouts(bytes32 _questionId, uint256 _winningOutcome) external onlyOwner {
    require(CT.payoutDenominator(condition) == 0, "Market already resolved");
    require(_winningOutcome < numOutcomes, "Invalid outcome");
    
    // Create payout array where winning outcome gets 100% and others get 0%
    uint[] memory payouts = new uint[](numOutcomes);
    for (uint i = 0; i < numOutcomes; i++) {
        if (i == _winningOutcome) {
            payouts[i] = 1000; // 100% payout (1000/1000)
        } else {
            payouts[i] = 0;     // 0% payout (0/1000)
        }
    }
    
    // Report winner-takes-all resolution
    CT.reportPayouts(_questionId, payouts);
}

/**
 * @notice Allows the owner to redeem outcome tokens held by the LMSR contract
 * @param indexSets Array of index sets representing the outcome positions to redeem
 */
function redeemContractShares(uint[] calldata indexSets) external onlyOwner {
    require(CT.payoutDenominator(condition) > 0, "Market not resolved yet");
    
    (address collateralToken, bytes32 parentCollectionId, bytes32 conditionId, ) = getRedeemParameters();
    
    CT.redeemPositions(
        IERC20(collateralToken),
        parentCollectionId,
        conditionId,
        indexSets
    );
}

/**
 * @notice Debug function to check what outcome tokens the LMSR contract holds
 * @return contractBalances Array of token balances held by the LMSR contract for each outcome
 */
function getContractBalances() public view returns (uint[] memory contractBalances) {
    contractBalances = new uint[](numOutcomes);
    
    for (uint i = 0; i < numOutcomes; i++) {
        bytes32 collectionId = CT.getCollectionId(bytes32(0), condition, 1 << i);
        uint positionId = CT.getPositionId(IERC20(token), collectionId);
        contractBalances[i] = CT.balanceOf(address(this), positionId);
    }
}

}