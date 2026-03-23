# lmsr-gem
Logarithmic Market Scoring Rule (LMSR) for Prediction Markets


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

# Binary market example

```ruby
binary = LmsrMarket.new(
  id: "election-2028",
  question: "Will Trump win the 2028 election?",
  outcomes: ["Yes", "No"],
  b: 150.0
)

binary.apply_trade!("user1", "Yes", 100) # costs ~$50-60 depending on current price
puts binary.probabilities # => {"Yes"=>0.62, "No"=>0.38}
```

# Multi-choice example
```ruby
election = LmsrMarket.new(
id: "2028-winner",
question: "Who wins 2028 presidential election?",
outcomes: ["Trump", "Harris", "RFK Jr", "Other"]
)
```

# Continuous (discretized) example

```ruby
dji = LmsrMarket.new(
id: "dji-april1",
question: "DJI closing value on April 1?",
outcomes: LmsrMarket.bucket_outcomes(38_000, 45_000, 14)  # 14 buckets
)
```

# "Final 4" style 

Just make multiple separate binary markets (recommended)
- Market 1: "Will Celtics make final 4?" (binary)
- Market 2: "Will Lakers make final 4?" etc.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/crypes/lmsr.
