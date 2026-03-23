# frozen_string_literal: true

require 'lmsr/market'

RSpec.describe LmsrMarket do

  describe "#initialize" do
    it "creates a market with correct initial state" do
      market = LmsrMarket.new
      expect(market.shares_outstanding).to eq([0.0, 0.0])
      expect(market.b).to eq(100.0)
    end

    it "raises error if fewer than 2 outcomes" do
      expect do
          LmsrMarket.new(initial_shares_outstanding: [1.0])
        end.to raise_error("Need at least 2 outcomes")
    end

    it "accepts initial shares_outstanding" do
      market = LmsrMarket.new(initial_shares_outstanding: [10.0, 20.0])
      expect(market.shares_outstanding).to eq([10.0, 20.0])
    end

    it "accepts initial probabilities" do
      market = LmsrMarket.new(initial_probabilities: [0.25, 0.25, 0.5])
      expect(market.probabilities).to eq([0.25, 0.25, 0.5])
    end
  end

  describe "#probabilities" do
    it "starts with equal probabilities" do
      market = LmsrMarket.new
      probs = market.probabilities
      expect(probs[0]).to eq(0.5)
      expect(probs[1]).to eq(0.5)
    end

    it "sums to 1.0" do
      market = LmsrMarket.new
      expect(market.probabilities.sum).to eq(1.0)
    end
  end

  describe "#price" do
    it "returns the probability of an outcome" do
      market = LmsrMarket.new
      expect(market.price(0)).to eq(0.5)
    end
  end

  describe "#cost" do
    it "returns 0 for 0 delta" do
      market = LmsrMarket.new
      expect(market.cost(0, 0.0)).to eq(0.0)
    end

    it "calculates positive cost for buying" do
      market = LmsrMarket.new
      expect(market.cost(0, 10.0)).to be > 0
    end
  end

  describe "#apply_trade!" do
    it "increases probability of bought outcome" do
      market = LmsrMarket.new
      market.apply_trade!(0, 10.0)
      expect(market.price(0)).to be > 0.5
      expect(market.price(1)).to be < 0.5
    end

    it "updates shares_outstanding" do
      market = LmsrMarket.new
      market.apply_trade!(0, 10.0)
      expect(market.shares_outstanding[0]).to eq(10.0)
    end

    it "raises error for invalid outcome index" do
      market = LmsrMarket.new
      expect {
        market.apply_trade!(2, 10.0)
      }.to raise_error("Invalid outcome index: 2")
    end

    it "decreases probability of sold outcome" do
      market = LmsrMarket.new(initial_shares_outstanding: [20.0, 20.0])
      initial_price = market.price(0)
      market.apply_trade!(0, -10.0)
      expect(market.price(0)).to be < initial_price
    end

    it "updates shares_outstanding" do
      market = LmsrMarket.new(initial_shares_outstanding: [100.0, 20.0])
      market.apply_trade!(0, -10.0)
      expect(market.shares_outstanding[0]).to eq(90.0)
    end
  end

  describe '#max_shares_to_trade' do
    let(:market) { LmsrMarket.new(b: 100.0) }

    before do
      # Start with balanced 50/50 market with some volume
      market.resize!(2)
      market.apply_trade!(0, 200) # outcome 0 now ~88.1%
      market.apply_trade!(1, 0) # outcome 1 ~11.9%
    end

    context 'when current probability is already close to target' do
      it 'returns 0 when within tolerance' do
        current_p = market.price(0) # ≈ 0.881
        delta = market.max_shares_to_trade(0, current_p, tolerance: 0.01)
        expect(delta).to eq(0.0)
      end

      it 'returns 0 when very close (small tolerance)' do
        delta = market.max_shares_to_trade(0, 0.88, tolerance: 0.005)
        expect(delta).to eq(0.0)
      end
    end

    context 'when wanting to increase probability significantly' do
      it 'returns large positive delta when target >> current' do
        delta = market.max_shares_to_trade(0, 0.95, tolerance: 1e-5)
        expect(delta).to be > 94
        expect(market.projected_probability(0, delta)).to be_within(0.001).of(0.95)
        market.apply_trade!(0, delta)
        expect(market.probabilities[0]).to be_within(1e-5).of(0.95)
      end

      it 'returns reasonable positive delta for moderate increase' do
        delta = market.max_shares_to_trade(0, 0.90, tolerance: 0.005)
        expect(delta).to be > 15.0
        expect(delta).to be < 16.0
        expect(market.projected_probability(0, delta)).to be_within(0.005).of(0.90)
        market.apply_trade!(0, delta)
        expect(market.probabilities[0]).to be_within(0.005).of(0.90)
      end
    end

    context 'when wanting to decrease probability' do
      it 'returns negative delta when target << current' do
        delta = market.max_shares_to_trade(0, 0.40, tolerance: 0.005)
        expect(delta).to be < -100
        expect(market.projected_probability(0, delta)).to be_within(0.005).of(0.40)
        market.apply_trade!(0, delta)
        expect(market.probabilities[0]).to be_within(0.005).of(0.40)
      end

      it 'returns small negative delta for small decrease' do
        delta = market.max_shares_to_trade(0, 0.85, tolerance: 0.01)
        expect(delta).to be < 0
        expect(delta.abs).to be < 100
      end
    end

    context 'extreme probability targets' do
      it 'handles target close to 0' do
        delta = market.max_shares_to_trade(0, 0.01, tolerance: 0.005)
        expect(delta).to be < -400
        market.apply_trade!(0, delta)
        expect(market.probabilities[0]).to be_within(0.005).of(0.01)
      end

      it 'handles target close to 1' do
        delta = market.max_shares_to_trade(0, 0.99, tolerance: 0.005)
        expect(delta).to be > 240.0
        market.apply_trade!(0, delta)
        expect(market.probabilities[0]).to be_within(0.005).of(0.99)
      end
    end

    context 'invalid inputs' do
      it 'raises when index is out of range' do
        expect {
          market.max_shares_to_trade(2, 0.5)
        }.to raise_error(ArgumentError, /Index out of range/)
      end

      it 'raises when p < 0' do
        expect {
          market.max_shares_to_trade(0, -0.1)
        }.to raise_error(ArgumentError, /p must be between/)
      end

      it 'raises when p > 1' do
        expect {
          market.max_shares_to_trade(0, 1.1)
        }.to raise_error(ArgumentError, /p must be between/)
      end

      it 'raises when tolerance <= 0' do
        expect {
          market.max_shares_to_trade(0, 0.5, tolerance: 0)
        }.to raise_error(ArgumentError, /tolerance must be positive/)
      end
    end

    context 'multi-outcome market' do
      before do
        market.resize!(4)
        market.apply_trade!(0, 100)
        market.apply_trade!(1, 50)
        market.apply_trade!(2, 20)
        # outcome 3 stays at ~ low probability
      end

      it 'correctly targets a low-probability outcome' do
        delta = market.max_shares_to_trade(3, 0.30, tolerance: 0.01)
        expect(delta).to be > 100
        expect(market.projected_probability(3, delta)).to be_within(0.015).of(0.30)
      end
    end

    context 'zero-volume market' do
      let(:fresh_market) { LmsrMarket.new(b: 100.0, initial_probabilities: [0.5, 0.5]) }

      it 'correctly computes delta from uniform starting point' do
        delta = fresh_market.max_shares_to_trade(0, 0.8, tolerance: 0.005)
        expect(delta).to be > 100
        expect(fresh_market.projected_probability(0, delta)).to be_within(0.005).of(0.8)
      end
    end
  end
end
