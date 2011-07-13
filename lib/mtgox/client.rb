require 'faraday/error'
require 'mtgox/ask'
require 'mtgox/bid'
require 'mtgox/buy'
require 'mtgox/sell'
require 'mtgox/connection'
require 'mtgox/max_bid'
require 'mtgox/min_ask'
require 'mtgox/request'

module MtGox
  class Client
    include MtGox::Connection
    include MtGox::Request

    ORDER_TYPES = {:sell => 1, :buy => 2}

    # Fetch the latest ticker data
    #
    # @authenticated false
    # @return [Hashie::Rash] with keys `buy` - current highest bid price, `sell` - current lowest ask price, `high` - highest price trade for the day, `low` - lowest price trade for the day, `last` - price of most recent trade, and `vol`
    # @example
    #   MtGox.ticker #=> <#Hashie::Rash buy=19.29 high=19.96 last=19.36 low=19.01 sell=19.375 vol=29470>
    def ticker
      get('/code/data/ticker.php')['ticker']
    end

    # Fetch both bids and asks in one call, for network efficiency
    #
    # @authenticated false
    # @return [Hash] with keys :asks and :asks, which contain arrays as described in {MtGox::Client#asks} and {MtGox::Clients#bids}
    # @example
    #   MtGox.offers
    def offers
      offers = get('/code/data/getDepth.php')
      asks = offers['asks'].sort_by do |ask|
        ask[0].to_f
      end.map! do |ask|
        Ask.new(*ask)
      end
      bids = offers['bids'].sort_by do |bid|
        -bid[0].to_f
      end.map! do |bid|
        Bid.new(*bid)
      end
      {:asks => asks, :bids => bids}
    end

    # Fetch open asks
    #
    # @authenticated false
    # @return [Array<MtGox::Ask>] an array of open asks, sorted in price ascending order
    # @example
    #   MtGox.asks
    def asks
      offers[:asks]
    end

    # Fetch open bids
    #
    # @authenticated false
    # @return [Array<MtGox::Bid>] an array of open bids, sorted in price descending order
    # @example
    #   MtGox.bids
    def bids
      offers[:bids]
    end

    # Fetch the lowest priced ask
    #
    # @authenticated false
    # @return [MtGox::MinAsk]
    # @example
    #   MtGox.min_ask
    def min_ask
      min_ask = asks.first
      MinAsk.instance.price = min_ask.price
      MinAsk.instance.amount = min_ask.amount
      MinAsk.instance
    end

    # Fetch the highest priced bid
    #
    # @authenticated false
    # @return [MtGox::MinBid]
    # @example
    #   MtGox.max_bid
    def max_bid
      max_bid = bids.first
      MaxBid.instance.price = max_bid.price
      MaxBid.instance.amount = max_bid.amount
      MaxBid.instance
    end

    # Fetch recent trades
    #
    # @authenticated false
    # @return [Array<Hashie::Rash>] an array of trades, sorted in chronological order. Each trade is a `Hashie::Rash` with keys `amount` - number of bitcoins traded, `price` - price they were traded at in US dollars, `date` - time and date of the trade (a `Time` object), and `tid` - the trade ID.
    # @example
    #   MtGox.trades[0, 3] #=> [<#Hashie::Rash amount=41 date=2011-06-14 11:26:32 -0700 price=18.5 tid="183747">, <#Hashie::Rash amount=5 date=2011-06-14 11:26:44 -0700 price=18.5 tid="183748">, <#Hashie::Rash amount=5 date=2011-06-14 11:27:00 -0700 price=18.42 tid="183749">]
    def trades
      get('/code/data/getTrades.php').each do |trade|
        trade['amount'] = trade['amount'].to_f
        trade['date'] = Time.at(trade['date'])
        trade['price'] = trade['price'].to_f
      end
    end

    # Fetch your current balance
    #
    # @authenticated true
    # @return [Hashie::Rash] with keys `btcs` - amount of bitcoins in your account and `usds` - amount of US dollars in your account
    # @example
    #   MtGox.balance #=> <#Hashie::Rash btcs=3.7 usds=12>
    def balance
      post('/code/getFunds.php', pass_params)
    end

    # Fetch your open orders, both buys and sells, for network efficiency
    #
    # @authenticated true
    # @return [Hash] with keys :buys and :sells, which contain arrays as described in {MtGox::Client#buys} and {MtGox::Clients#sells}
    # @example
    #   MtGox.orders
    def orders
      parse_orders(post('/code/getOrders.php', pass_params)['orders'])
    end

    # Fetch your open buys
    #
    # @authenticated true
    # @return [Array<MtGox::Buy>] an array of your open bids, sorted by date
    # @example
    #   MtGox.buys
    def buys
      orders[:buys]
    end

    # Fetch your open sells
    #
    # @authenticated true
    # @return [Array<MtGox::Sell>] an array of your open asks, sorted by date
    # @example
    #   MtGox.sells
    def sells
      orders[:sells]
    end

    # Place a limit order to buy BTC
    #
    # @authenticated true
    # @param amount [Numeric] the number of bitcoins to purchase
    # @param price [Numeric] the bid price in US dollars
    # @return [Hash] with keys :buys and :sells, which contain arrays as described in {MtGox::Client#buys} and {MtGox::Clients#sells}
    # @example
    #   # Buy one bitcoin for $0.011
    #   MtGox.buy! 1.0, 0.011
    def buy!(amount, price)
      parse_orders(post('/code/buyBTC.php', pass_params.merge({:amount => amount, :price => price}))['orders'])
    end

    # Place a limit order to sell BTC
    #
    # @authenticated true
    # @param amount [Numeric] the number of bitcoins to sell
    # @param price [Numeric] the ask price in US dollars
    # @return [Hash] with keys :buys and :sells, which contain arrays as described in {MtGox::Client#buys} and {MtGox::Clients#sells}
    # @example
    #   # Sell one bitcoin for $100
    #   MtGox.sell! 1.0, 100.0
    def sell!(amount, price)
      parse_orders(post('/code/sellBTC.php', pass_params.merge({:amount => amount, :price => price}))['orders'])
    end

    # Cancel an open order
    #
    # @authenticated true
    # @overload cancel(oid)
    #   @param oid [String] an order ID
    #   @return [Hash] with keys :buys and :sells, which contain arrays as described in {MtGox::Client#buys} and {MtGox::Clients#sells}
    #   @example
    #     my_order = MtGox.orders.first
    #     MtGox.cancel my_order.oid
    #     MtGox.cancel 1234567890
    # @overload cancel(order)
    #   @param order [Hash] a hash-like object, with keys `oid` - the order ID of the transaction to cancel and `type` - the type of order to cancel (`1` for sell or `2` for buy)
    #   @return [Hash] with keys :buys and :sells, which contain arrays as described in {MtGox::Client#buys} and {MtGox::Clients#sells}
    #   @example
    #     my_order = MtGox.orders.first
    #     MtGox.cancel my_order
    #     MtGox.cancel {"oid" => "1234567890", "type" => 2}
    def cancel(args)
      if args.is_a?(Hash)
        order = args.delete_if{|k, v| !['oid', 'type'].include?(k.to_s)}
        parse_orders(post('/code/cancelOrder.php', pass_params.merge(order))['orders'])
      else
        orders = post('/code/getOrders.php', pass_params)['orders']
        order = orders.find{|order| order['oid'] == args.to_s}
        if order
          order = order.delete_if{|k, v| !['oid', 'type'].include?(k.to_s)}
          parse_orders(post('/code/cancelOrder.php', pass_params.merge(order))['orders'])
        else
          raise Faraday::Error::ResourceNotFound, {:status => 404, :headers => {}, :body => "Order not found."}
        end
      end
    end

    # Transfer bitcoins from your Mt. Gox account into another account
    #
    # @authenticated true
    # @param amount [Numeric] the number of bitcoins to withdraw
    # @param btca [String] the bitcoin address to send to
    # @return [Array<Hashie::Rash>]
    # @example
    #   # Withdraw 1 BTC from your account
    #   MtGox.withdraw! 1.0, "1KxSo9bGBfPVFEtWNLpnUK1bfLNNT4q31L"
    def withdraw!(amount, btca)
      post('/code/withdraw.php', pass_params.merge({:group1 => "BTC", :amount => amount, :btca => btca}))
    end

    private

    def parse_orders(orders)
      buys = []
      sells = []
      orders.sort_by{|order| order['date']}.each do |order|
        case order['type']
        when ORDER_TYPES[:sell]
          sells << Sell.new(order)
        when ORDER_TYPES[:buy]
          buys << Buy.new(order)
        end
      end
      {:buys => buys, :sells => sells}
    end

    def pass_params
      {:name => MtGox.username, :pass => MtGox.password}
    end
  end
end
