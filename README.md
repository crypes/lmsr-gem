# lmsr-gem
Logarithmic Market Scoring Rule (LMSR) for Prediction Markets

A pure Ruby implementation of the LMSR automated market maker. This gem handles the core mathematical logic (pricing, cost functions, probabilities) for prediction markets. It is designed to be embedded in larger applications that manage user accounts, balances, and market metadata.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add lmsr
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install lmsr
```

## Usage

### Initialization

The `LmsrMarket` class is initialized with the liquidity parameter `b` and either `initial_shares_outstanding` (array of shares) or `initial_probabilities` (array of probabilities).

**Option 1: Initialize with Default Shares (0.0)**
If you just want a fresh market with N outcomes starting at equal probability, pass an array of zeros.

```ruby
require 'lmsr/market'

# Create a binary market (2 outcomes) with liquidity parameter b=100.0
# Starting shares are 0.0 for both outcomes.
market = LmsrMarket.new(
  b: 100.0,
  initial_shares_outstanding: [0.0, 0.0]
)
```

**Option 2: Initialize with Specific Shares**
Load an existing market state or start with a bias.

```ruby
# Create a market with 4 outcomes and specific initial shares distribution
initial_shares = [10.0, 20.0, 5.0, 5.0]
market = LmsrMarket.new(
  b: 150.0,
  initial_shares_outstanding: initial_shares
)
```

**Option 3: Initialize with Probabilities**
Start the market with specific implied probabilities. The engine will calculate the necessary share distribution.

```ruby
# Start a 3-outcome market with probabilities [0.1, 0.2, 0.7]
market = LmsrMarket.new(
  b: 100.0,
  initial_probabilities: [0.1, 0.2, 0.7]
)
```

### Market Information

Get current prices and probabilities.

```ruby
# Get probability of outcome 0 (e.g., "Yes")
prob_yes = market.price(0) # => 0.5 (initially)

# Get all probabilities
all_probs = market.probabilities # => [0.5, 0.5]

# Calculate cost to buy 10 shares of outcome 0
cost = market.cost(0, 10.0) # => ~5.0
```

### Trading

Execute trades to update market state.

```ruby
# Buy 10 shares of outcome 0
# NOTE: user validation (funds, holdings) must be done externally before calling this.
result = market.apply_trade!(0, 10.0) 
puts "Cost: #{result[:cost]}"
puts "New Price: #{result[:new_probability]}"

# Sell 5 shares of outcome 0
# Negative delta means selling.
result = market.apply_trade!(0, -5.0)
puts "Proceeds: #{result[:cost].abs}" # negative cost = proceeds
```

### Determining Trade Size

Calculate how many shares to trade to move the market price to a user's belief.

```ruby
# User believes probability of outcome 0 is 0.8
# Calculate shares to buy/sell to move price from current (e.g. 0.5) to 0.8
delta = market.max_shares_to_trade(0, 0.8)

if delta > 0
  # buy |delta| shares
  market.apply_trade!(0, delta)
elsif delta < 0
  # Sell |delta| shares
  market.apply_trade!(0, delta)
end
```

### Resolution

Resolve the market to a winning outcome.

```ruby
market.resolve!(0) # Outcome 0 wins
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/crypes/lmsr.
