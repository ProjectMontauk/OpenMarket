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
import "./FakeDai.sol";

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
   * @param _oracle The address for the EOA/contract which will act as the
      oracle for this condition
   * @param _questionId The question ID (needs to be unique)
   * @param _numOutcomes The number of different outcomes available
   * @param bInput The liquidity parameter b for the LMSR market maker
   * @param _initialSubsidy The initial DAI subsidy to deposit in the contract
   * @param _overround How much 'profit' does the AMM claim? Note that this is
   * represented in bips. Therefore inputting 300 represents 0.30%
   */
  function setup(
    address _oracle,
    bytes32 _questionId,
    uint _numOutcomes,
    uint bInput,
    uint _initialSubsidy,
    uint _overround
  ) public onlyOwner() {
    require(init == false,'Already init');
    require(_overround > 0,'Cannot have 0 overround');
    CT.prepareCondition(_oracle, _questionId, _numOutcomes);
    condition = CT.getConditionId(_oracle, _questionId, _numOutcomes);

    numOutcomes = _numOutcomes;
    int128 n = ABDKMath.fromUInt(_numOutcomes);
    int128 initial_b = getTokenEth(token, bInput);
    b = initial_b;

    // Transfer the initial subsidy to the contract
    IERC20(token).safeTransferFrom(msg.sender, address(this), _initialSubsidy);

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
    emit DebugMinting(_outcome, contractBalance, n_outcome_tokens, willMint);
    
    if (willMint) {
        IERC20(token).approve(address(CT), getTokenWeiUp(token, _amount));
        CT.splitPosition(IERC20(token), bytes32(0), condition,
            getPositionAndDustPositions(_outcome), n_outcome_tokens);
    }
    CT.safeTransferFrom(address(this), msg.sender, pos, n_outcome_tokens, '');
  }

  function buy(
    uint256 _outcome,
    int128 _amount
  ) public onlyAfterInit returns (int128 _price) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    require(CT.payoutDenominator(condition) == 0, 'Market already resolved');

    (int128 new_cost, int128 price_, int128 new_total_shares) = _calculateBuyPrice(q, _outcome, _amount, total_shares, current_cost, numOutcomes);

    // Apply overround as a multiplier to the buy price
    int128 overround_multiplier = ABDKMath.add(ABDKMath.fromUInt(1), overround); // 1 + overround
    int128 price_with_overround = ABDKMath.mul(price_, overround_multiplier);

    uint token_cost = getTokenWeiUp(token, price_with_overround);
    emit BuyTokenCost(token_cost, price_with_overround);
    require(IERC20(token).transferFrom(msg.sender, address(this), token_cost), 'Error transferring tokens');

    // Now update the actual inventory and state
    q[_outcome] = ABDKMath.add(q[_outcome], _amount);
    total_shares = new_total_shares;
    current_cost = new_cost;

    _mintAndTransferOutcomeTokens(_outcome, _amount);

    return price_with_overround;
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

  function sell(uint256 _outcome, int128 _amount) public onlyAfterInit returns (int128 refund) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    require(CT.payoutDenominator(condition) == 0, "Market already resolved");
    require(q[_outcome] >= _amount, "Not enough shares to sell");

    // 1. Calculate refund BEFORE updating state
    (int128 new_cost, int128 refund_, int128 new_total_shares) = _calculateSellRefund(
        q, _outcome, _amount, total_shares, current_cost, numOutcomes
    );

    // 2. Check if user is trying to sell more than possible
    uint maxSellable = getMaxSellableAmount(_outcome);
    uint n_outcome_tokens = getTokenWeiDown(token, _amount);
    require(n_outcome_tokens <= maxSellable, string(abi.encodePacked("Max sellable: ", maxSellable, " tokens")));
    
    // 3. Collect shares from user
    uint pos = CT.getPositionId(IERC20(token), CT.getCollectionId(bytes32(0), condition, 1 << _outcome));
    
    try CT.safeTransferFrom(msg.sender, address(this), pos, n_outcome_tokens, "") {
        // Success - continue
    } catch Error(string memory reason) {
        emit SplitPositionError("safeTransferFrom failed", reason);
        revert(string(abi.encodePacked("safeTransferFrom failed: ", reason)));
    }

    // 4. Check if we need to mint missing tokens before burning
    uint[] memory partition = getPositionAndDustPositions(_outcome);
    bool needToMint = false;
    uint tokensToMint = 0;
    
    // Check if we have enough tokens for all outcomes in the partition
    for (uint i = 0; i < partition.length; i++) {
        uint posId = CT.getPositionId(IERC20(token), CT.getCollectionId(bytes32(0), condition, partition[i]));
        uint balance = CT.balanceOf(address(this), posId);
        if (balance < n_outcome_tokens) {
            needToMint = true;
            tokensToMint = n_outcome_tokens - balance;
            break; // We only need to mint once since splitPosition mints for all outcomes
        }
    }
    
    // Mint missing tokens if needed
    if (needToMint) {
        IERC20(token).approve(address(CT), tokensToMint);
        CT.splitPosition(IERC20(token), bytes32(0), condition, partition, tokensToMint);
    }
    
    // 5. Burn outcome tokens and get DAI back
    CT.mergePositions(IERC20(token), bytes32(0), condition, partition, n_outcome_tokens);

    // 4. Update the inventory and state
    q[_outcome] = ABDKMath.sub(q[_outcome], _amount);
    total_shares = new_total_shares;
    current_cost = new_cost;

    // 5. Pay refund to user
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
    uint contractBalance = IERC20(token).balanceOf(address(this));
    uint theoreticalCost = getTokenWei(token, current_cost);
    if (contractBalance > theoreticalCost) {
        return contractBalance - theoreticalCost;
    } else {
        return 0;
    }
}

event FeesWithdrawn(address indexed to, uint256 amount);

function withdrawFees() public onlyOwner {
    uint actualBalance = IERC20(token).balanceOf(address(this));
    uint theoreticalCost = getTokenWei(token, current_cost);
    require(actualBalance > theoreticalCost, "No fees to withdraw");
    uint fees = actualBalance - theoreticalCost;
    IERC20(token).safeTransfer(owner(), fees);
    emit FeesWithdrawn(owner(), fees);
}

function debugFees() public view returns (uint contractBalance, uint theoreticalCost) {
    contractBalance = IERC20(token).balanceOf(address(this));
    theoreticalCost = getTokenWei(token, current_cost);
}

function getPositionInfo(uint256 _outcome) public view returns (uint256 positionId, uint256 balance) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    bytes32 collectionId = CT.getCollectionId(bytes32(0), condition, 1 << _outcome);
    positionId = CT.getPositionId(IERC20(token), collectionId);
    balance = CT.balanceOf(address(this), positionId);
}

function getMaxSellableAmount(uint256 _outcome) public view returns (uint256) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    
    // Get partner outcome (the other outcome)
    uint256 partnerOutcome = _outcome == 0 ? 1 : 0;
    
    // Get contract balance
    uint256 contractBalance = IERC20(token).balanceOf(address(this));
    
    // Get existing partner outcome tokens
    uint256 partnerPosId = CT.getPositionId(IERC20(token), 
        CT.getCollectionId(bytes32(0), condition, 1 << partnerOutcome));
    uint256 existingPartnerTokens = CT.balanceOf(address(this), partnerPosId);
    
    // Max sellable = contract balance + existing partner tokens
    return contractBalance + existingPartnerTokens;
}

}