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
  int128 private alpha;
  int128 private current_cost;
  int128 private total_shares;
  int128 public initial_subsidy;

  bytes32 public condition;
  ConditionalTokens private CT;
  address public token;

  bool private init;

  // 64.64 fixed-point representation of e (Euler's number)
  int128 constant E_64x64 = 0x2B7E151628AED2A6; // ≈ 2.718281828459045

  // Dummy variable for redeployment uniqueness
  uint256 public dummyVar = 42;

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
   * _subsidyToken Which ERC-20 token will be used to purchase and redeem
      outcome tokens for this condition
   * @param _subsidy How much initial funding is used to seed the market maker.
   * @param _overround How much 'profit' does the AMM claim? Note that this is
   * represented in bips. Therefore inputting 300 represents 0.30%
   */
  function setup(
    address _oracle,
    bytes32 _questionId,
    uint _numOutcomes,
    uint _subsidy,
    uint _overround
  ) public onlyOwner() {
    require(init == false,'Already init');
    require(_overround > 0,'Cannot have 0 overround');
    CT.prepareCondition(_oracle, _questionId, _numOutcomes);
    condition = CT.getConditionId(_oracle, _questionId, _numOutcomes);

    IERC20(token).safeTransferFrom(msg.sender, address(this), _subsidy);

    numOutcomes = _numOutcomes;
    int128 n = ABDKMath.fromUInt(_numOutcomes);
    initial_subsidy = getTokenEth(token, _subsidy);

    int128 overround = ABDKMath.divu(_overround, 10000); //TODO: if the overround is too low, then the exp overflows
    alpha = ABDKMath.div(overround, ABDKMath.mul(n,ABDKMath.ln(n)));
    b = ABDKMath.mul(ABDKMath.mul(initial_subsidy, n), alpha);

    for(uint i=0; i<_numOutcomes; i++) {
      q.push(initial_subsidy);
    }

    init = true;

    total_shares = ABDKMath.mul(initial_subsidy, n);
    current_cost = cost();
  }

  /**
   * @notice This function is used to buy outcome tokens.
   * @param _outcome The outcome(s) which a user is buying tokens for.
      Note: This is the integer representation for the bit array.
   * @param _amount This is the number of outcome tokens purchased
   * @return _price The cost to purchase _amount number of tokens
   */
  function buy(
    uint256 _outcome,
    int128 _amount
  ) public onlyAfterInit() returns (int128 _price){
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    require(CT.payoutDenominator(condition) == 0, 'Market already resolved');

    q[_outcome] = ABDKMath.add(q[_outcome], _amount);
    total_shares = ABDKMath.add(total_shares, _amount);
    b = ABDKMath.mul(total_shares, alpha);

    int128 sum_total;
    for(uint i=0; i< numOutcomes; i++) {
      sum_total = ABDKMath.add(sum_total,
        ABDKMath.exp(
          ABDKMath.div(q[i], b)
          ));
    }

    int128 new_cost = ABDKMath.mul(b,ABDKMath.ln(sum_total));
    _price = ABDKMath.sub(new_cost,current_cost);
    current_cost = new_cost;

    uint token_cost = getTokenWei(token, _price);
    uint n_outcome_tokens = getTokenWei(token, _amount);
    uint pos = CT.getPositionId(IERC20(token),
      CT.getCollectionId(bytes32(0), condition, 1 << _outcome));

    require(IERC20(token).transferFrom(msg.sender, address(this), token_cost),
      'Error transferring tokens');

    if(CT.balanceOf(address(this), pos) < n_outcome_tokens) {
      IERC20(token).approve(address(CT), getTokenWei(token, _amount));
      CT.splitPosition(IERC20(token), bytes32(0), condition,
        getPositionAndDustPositions(_outcome), n_outcome_tokens);
      }
    CT.safeTransferFrom(address(this), msg.sender,
      pos, n_outcome_tokens, '');
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
    int128 TB = total_shares;

    for(uint j=0; j< numOutcomes; j++) {
      if((_outcome & (1<<j)) != 0) {
        newq[j] = ABDKMath.add(q[j], _amount);
        TB = ABDKMath.add(TB, _amount);
      } else {
        newq[j] = q[j];
      }
    }

    int128 _b = ABDKMath.mul(TB, alpha);

    for(uint i=0; i< numOutcomes; i++) {
      sum_total = ABDKMath.add(sum_total,
        ABDKMath.exp(
          ABDKMath.div(newq[i], _b)
          ));
    }

    return ABDKMath.mul(_b, ABDKMath.ln(sum_total));
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

  function getTokenWei(
    address _token,
    int128 _amount
  ) public view returns (uint) {
    uint d = ERC20(_token).decimals();
    uint multiplier = 10 ** d;
    
    // Debug: Check for potential overflow
    require(_amount >= 0, "Amount must be non-negative");
    
    // Check if the multiplication would overflow
    // For 18 decimals, multiplier = 10^18 = 1000000000000000000
    // If _amount is too large, mulu will revert
    uint result = ABDKMath.mulu(_amount, multiplier);
    
    return result;
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

  
  function sell(uint256 _outcome, int128 _amount) public onlyAfterInit returns (int128 refund) {
    require(_outcome < numOutcomes, "Invalid outcome index");
    require(_amount > 0, "Amount must be positive");
    require(CT.payoutDenominator(condition) == 0, "Market already resolved");

    // Re-calculating liquidity parameter by subtracting out the amount of shares sold
    require(q[_outcome] >= _amount, "Not enough shares to sell");
    q[_outcome] = ABDKMath.sub(q[_outcome], _amount);
    total_shares = ABDKMath.sub(total_shares, _amount);
    b = ABDKMath.mul(total_shares, alpha);

    // Calculating the cost of the new state after selling shares with new liquidity parameter C(q', q')
    int128 sum_total;
    for (uint i = 0; i < numOutcomes; i++) {
        sum_total = ABDKMath.add(sum_total, ABDKMath.exp(ABDKMath.div(q[i], b)));
    }
    int128 new_cost = ABDKMath.mul(b, ABDKMath.ln(sum_total));

    // Calculating the refund amount by the difference between Cost = C(q',q') - C(q,q)
    refund = ABDKMath.sub(current_cost, new_cost);
    
    // Re-setting the C(q',q') the updated state to the old state in preparation for the next operation
    current_cost = new_cost;

    // getTokenWei converts the selling collateral into the smallest unit of the token
    uint n_outcome_tokens = getTokenWei(token, _amount);
    uint pos = CT.getPositionId(IERC20(token), CT.getCollectionId(bytes32(0), condition, 1 << _outcome));
    CT.safeTransferFrom(msg.sender, address(this), pos, n_outcome_tokens, "");

    uint token_refund = getTokenWei(token, refund);
    IERC20(token).safeTransfer(msg.sender, token_refund);

    return refund;
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
    b = ABDKMath.mul(total_shares, alpha);

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

}