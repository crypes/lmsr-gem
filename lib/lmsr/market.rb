# frozen_string_literal: true

# lmsr/market.rb
# Zero dependencies - pure Ruby LMSR prediction market engine

# Logarithmic Market Scoring Rule (LMSR) market engine.
#
# This class implements a pure mathematical prediction market using the LMSR model.
# It handles pricing, cost calculation, and state updates for binary and multi-outcome
# markets. User holdings, market metadata (id, question, outcome labels), and
# persistence are intentionally managed outside this class.
#
# @see https://en.wikipedia.org/wiki/Logarithmic_market_scoring_rule
# @see Chen, Yiling & Pennock, David M. (2007). "A Utility Framework for
#      Bounded-Loss Market Makers"
class LmsrMarket
  # @return [Float] liquidity parameter — controls price sensitivity to trades
  #                 (higher b → slower price movement)
  attr_reader :b

  # @return [Array<Float>] current shares outstanding for each outcome (index-based)
  #                        Negative values are normal and expected when using
  #                        initial_probabilities with low-probability outcomes.
  attr_reader :shares_outstanding

  # @return [Integer, nil] index of the winning outcome after resolution,
  #                        or nil if unresolved
  attr_reader :resolved_to_index

  # Create a new LMSR market instance.
  #
  # @param b [Numeric] liquidity parameter (default: 100.0)
  # @param initial_shares_outstanding [Array<Numeric>, nil] optional starting
  #        shares for each outcome (non-negative)
  # @param initial_probabilities [Array<Numeric>, nil] optional starting
  #        probabilities [p0, p1, ..., pn] summing to ~1.0
  #
  # @raise [ArgumentError] if both initial_shares_outstanding and
  #        initial_probabilities are provided
  # @raise [ArgumentError] if probabilities do not sum to ~1.0 or contain invalid values
  # @raise [ArgumentError] if initial shares contain negative values
  #
  # @note Exactly one of initial_shares_outstanding or initial_probabilities
  #       should be provided if you want a non-uniform starting state.
  #       If neither is given, all shares start at 0.0.
  def initialize(b: 100.0,
                 initial_shares_outstanding: nil,
                 initial_probabilities: nil)
    @b = b.to_f

    if initial_shares_outstanding && initial_probabilities
      raise ArgumentError, "Cannot provide both initial_shares_outstanding and initial_probabilities"
    end

    if initial_probabilities
      raise ArgumentError, "initial_probabilities must be an array" unless initial_probabilities.is_a?(Array)
      total = initial_probabilities.sum
      raise ArgumentError, "Probabilities must sum to ~1.0 (got #{total})" unless (total - 1.0).abs < 1e-9

      @shares_outstanding = initial_probabilities.map do |p|
        raise ArgumentError, "Probabilities must be > 0 and < 1" unless p.between?(1e-6, 1 - 1e-6)
        @b * Math.log(p)
      end
    elsif initial_shares_outstanding
      raise ArgumentError, "initial_shares_outstanding must be an array" unless initial_shares_outstanding.is_a?(Array)
      raise ArgumentError, "Shares must be non-negative" if initial_shares_outstanding.any? { |q| q < 0 }
      raise ArgumentError, "Need at least 2 outcomes" if initial_shares_outstanding.size < 2
      @shares_outstanding = initial_shares_outstanding.map(&:to_f)
    else
      @shares_outstanding = [0.0] * 2   # minimal default — caller should resize if needed
    end

    @resolved_to_index = nil
  end

  # Current implied probabilities for each outcome.
  #
  # @return [Array<Float>] array of probabilities [p0, p1, ..., pn] summing to 1.0
  def probabilities
    exps = @shares_outstanding.map { |q| Math.exp(q / @b) }
    sum = exps.sum
    exps.map { |e| (sum > 0 ? e / sum : 0.0).clamp(0.0, 1.0) }
  end

  # Current price (implied probability) for a single outcome.
  #
  # @param index [Integer] 0-based outcome index
  # @return [Float] current price (probability) for that outcome
  # @raise [IndexError] if index is out of bounds
  def price(index)
    probabilities.fetch(index)
  end

  # Cost to buy (+delta) or sell (-delta) delta shares of the given outcome.
  #
  # @param index [Integer] outcome index
  # @param delta [Numeric] change in shares (>0 = buy, <0 = sell)
  # @return [Float] net cost to the trader
  #                  positive → trader pays this amount
  #                  negative → trader receives this amount
  # @raise [IndexError] if index is out of bounds
  def cost(index, delta)
    old_cost = cost_function(@shares_outstanding)
    new_s = @shares_outstanding.dup
    new_s[index] += delta
    new_cost = cost_function(new_s)
    new_cost - old_cost
  end

  private

  def cost_function(shares)
    sum = shares.map { |q| Math.exp(q / @b) }.sum
    @b * Math.log(sum + 1e-300)   # avoid log(0)
  end

  public

  # Apply a trade by updating shares_outstanding for one outcome.
  #
  # This method only modifies market state — it does **not** check user balances,
  # ownership, or funds. The caller is responsible for validation.
  #
  # @param index [Integer] outcome index
  # @param delta [Numeric] change in shares (>0 = buy, <0 = sell)
  # @return [Hash] trade result
  #   * :cost [Float] — net cost (positive = paid, negative = received)
  #   * :new_probability [Float] — updated price after trade
  # @raise [RuntimeError] if market is already resolved
  # @raise [ArgumentError] if index is invalid
  def apply_trade!(index, delta)
    raise "Market already resolved" if @resolved_to_index
    raise ArgumentError, "Invalid outcome index: #{index}" if index < 0 || index >= @shares_outstanding.size

    @shares_outstanding[index] += delta

    {
      cost: cost(index, delta),
      new_probability: price(index)
    }
  end

  # Resolve the market to a winning outcome.
  #
  # @param winning_index [Integer] index of the winning outcome
  # @return [String] confirmation message
  # @raise [RuntimeError] if already resolved
  # @raise [ArgumentError] if winning_index is invalid
  def resolve!(winning_index)
    raise "Already resolved" if @resolved_to_index
    raise ArgumentError, "Invalid winning index" if winning_index < 0 || winning_index >= @shares_outstanding.size

    @resolved_to_index = winning_index
    "Market resolved to outcome index #{winning_index}"
  end

  # Payout multiplier per share for the winning outcome.
  #
  # @return [Float] 1.0 if resolved, 0.0 if unresolved
  def payout_per_share
    @resolved_to_index.nil? ? 0.0 : 1.0
  end

  # Calculate total payout for a user given their holdings array.
  #
  # @param user_holdings_array [Array<Numeric>] user's shares per outcome
  # @return [Float] total payout if resolved, 0.0 otherwise
  def calculate_payout(user_holdings_array)
    return 0.0 unless @resolved_to_index
    user_holdings_array[@resolved_to_index].to_f * payout_per_share
  end

  # Resize the market to support more outcomes (rarely needed).
  #
  # Appends zero shares for new outcomes.
  #
  # @param new_size [Integer] desired number of outcomes
  # @raise [ArgumentError] if attempting to shrink the market
  def resize!(new_size)
    return if new_size == @shares_outstanding.size
    raise ArgumentError, "Cannot shrink market" if new_size < @shares_outstanding.size
    @shares_outstanding.concat([0.0] * (new_size - @shares_outstanding.size))
  end

  # Calculates the ideal number of shares to buy or sell for a given outcome
  # so that the resulting market probability is as close as possible to the
  # caller's believed true probability `p`, within the given tolerance.
  #
  # Uses iterative search (binary search) to find the delta, since the exact
  # analytical solution can be numerically unstable near p=0 or p=1.
  #
  # @param index [Integer] 0-based index of the outcome
  # @param p [Numeric] caller's subjective probability for this outcome (0.0 to 1.0)
  # @param tolerance [Numeric] maximum acceptable absolute difference between
  #        target p and achieved probability (default: 1e-6)
  #
  # @return [Float] recommended share delta:
  #   - positive → number of shares to **buy**
  #   - negative → absolute number of shares to **sell**
  #   - zero    → no desirable trade (current probability is within tolerance)
  #
  # @raise [ArgumentError] if index is out of range
  # @raise [ArgumentError] if p is not between 0.0 and 1.0
  # @raise [ArgumentError] if tolerance <= 0
  #
  # @note
  #   - This method does **not** consider budget, holdings, or liquidity limits.
  #   - Caller must cap the result for real trades:
  #     • buys: by available funds / cost
  #     • sells: by owned shares
  #   - Tolerance controls precision vs. performance trade-off.
  #   - Returns 0.0 if current probability is already within tolerance of p.
  #
  # @example
  #   market.max_shares_to_trade(0, 0.85, tolerance: 0.001)
  #   # => approximate delta that gets probability within ±0.001 of 0.85
  def max_shares_to_trade(index, p, tolerance: 1e-6)
    raise ArgumentError, "Index out of range" if index < 0 || index >= @shares_outstanding.size
    raise ArgumentError, "p must be between 0.0 and 1.0" unless p.between?(0.0, 1.0)
    raise ArgumentError, "tolerance must be positive" if tolerance <= 0.0

    current_p = price(index)
    return 0.0 if (current_p - p).abs <= tolerance

    # Early exit for extreme targets (numerical stability)
    return 0.0 if p <= tolerance || p >= 1 - tolerance

    # Binary search bounds — start wide, expand if needed
    low_shares  = p < current_p ? -1_000.0 : 0.0 # must sell to lower p
    high_shares = p > current_p ? 1_000.0 : 0.0 # must buy to raise p

    # Widen bounds if not in range
    # widen low boundary
    loop do
      lower_p = projected_probability(index, low_shares)
      break if lower_p - tolerance < current_p

      low_shares += low_shares
    end
    # widen high boundary
    loop do
      higher_p = projected_probability(index, high_shares)
      break if higher_p + tolerance > current_p

      high_shares += high_shares
    end

    # now do successive approximation
    loop do
      mid_shares = (low_shares + high_shares) / 2
      mid_p = projected_probability(index, mid_shares)
      if (mid_p - p).abs <= tolerance
        return mid_shares
      elsif mid_p < p
        low_shares = mid_shares
      else
        high_shares = mid_shares
      end
    end

    # somehow didn't find - return zero
    0.0
  end

  # Helper: what would the probability of outcome[index] be if we added delta shares?
  def projected_probability(index, delta)
    new_s = @shares_outstanding.dup
    new_s[index] += delta
    exps = new_s.map { |q| Math.exp(q / @b) }
    sum = exps.sum
    return 0.0 if sum <= 0
    (exps[index] / sum).clamp(0.0, 1.0)
  end


end
