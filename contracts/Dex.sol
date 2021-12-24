// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import '../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol';


contract Dex {

    using SafeMath for uint;

    enum Side {BUY, SELL}

    struct Token {
        uint id;
        bytes32 ticker;
        address tokenAddress;
    }

    struct Order {
        uint id;
        address trader;
        Side side;
        bytes32 ticker;
        uint amount;
        uint filled;
        uint price;
        uint date;
    }

    struct Trade {
        uint id;
        uint orderId;
        bytes32 ticker;
        address maker;
        address taker;
        uint amount;
        uint price;
        uint date;
    }

    mapping(bytes32 => Token) public tokens;
    mapping(address => mapping (bytes32 => uint)) public traderBalances;
    mapping (bytes32 => mapping(uint => Order[])) public orderBook;

    bytes32[] public tokenList;
    Order[] public orderList;
    Trade[] public tradeList;

    address public admin;
    bytes32 constant DAI = bytes32('DAI');

    event NewTrade(
        uint tradeId,
        uint orderId,
        bytes32 indexed ticker,
        address indexed maker,
        address indexed taker,
        uint amount,
        uint price,
        uint date
    );

    constructor() {
        admin = msg.sender;
    }

    function getOrders(bytes32 ticker, Side side) external view returns(Order[] memory) {
        return orderBook[ticker][uint(side)];
    }

    function getTokens() external view returns(Token[] memory) {
        Token[] memory _tokens = new Token[](tokenList.length);
        for (uint i = 0; i < tokenList.length; i++) {
            _tokens[i] = Token(
                tokens[tokenList[i]].id,
                tokens[tokenList[i]].ticker,
                tokens[tokenList[i]].tokenAddress
            );
        }
      return _tokens;
    }

    function addToken(bytes32 ticker, address tokenAddress) external onlyAdmin {
        tokens[ticker] = Token(tokenList.length, ticker, tokenAddress);
        tokenList.push(ticker);
    }

    function deposit(uint amount, bytes32 ticker) external tokenExists(ticker) {
        IERC20(tokens[ticker].tokenAddress).transferFrom(msg.sender, address(this), amount);

        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(amount);
    }

    function withdraw(uint amount, bytes32 ticker) external tokenExists(ticker) {
        require(traderBalances[msg.sender][ticker] >= amount, 'Not enought balance');

        IERC20(tokens[ticker].tokenAddress).transfer(msg.sender, amount);
        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(amount);
    }

    function createLimitOrder(bytes32 ticker, uint amount, uint price, Side side) external tokenExists(ticker) tokenIsNotDai(ticker) hasEnoughtBalance(ticker, amount, price, side) {
        Order memory order = Order(orderList.length, msg.sender, side, ticker, amount, 0, price, block.timestamp);
        orderList.push(order);

        Order[] storage orders = orderBook[ticker][uint(side)];

        for (uint i = orders.length > 0 ? orders.length - 1 : 0; i > 0; i = i.sub(1)) {
            if (side == Side.BUY && orders[i - 1].price >= order.price) {
                orders[i] = order;
                break;
            }

            if (side == Side.SELL && orders[i - 1].price <= order.price) {
                orders[i] = order;
                break;
            }

            orders[i] = orders[i - 1];
        }
    }

    function createMarketOrder(bytes32 ticker, uint amount, Side side) external tokenExists(ticker) tokenIsNotDai(ticker) hasEnoughtMarketBalance(ticker, amount, side) {
        Order[] storage orders = orderBook[ticker][uint(side == Side.BUY ? Side.SELL : Side.BUY)];

        uint remaining = amount;
        uint i = 0;

        while (i < orders.length && remaining > 0) {
            Order storage order = orders[i]; 
            uint available = order.amount.sub(order.filled);
            uint matched = (remaining > available) ? available : remaining;

            remaining -= matched;
            order.filled += matched;

            Trade memory trade = Trade(tradeList.length, order.id, ticker, order.trader, msg.sender, matched, order.price, block.timestamp);
            tradeList.push(trade);
            emit NewTrade(trade.id, trade.orderId, trade.ticker, trade.maker, trade.taker, trade.amount, trade.price, trade.date);

            if (side == Side.SELL) {
                traderBalances[msg.sender][ticker] -= matched;
                traderBalances[msg.sender][DAI] += matched * order.price;

                traderBalances[order.trader][ticker] += matched;
                traderBalances[order.trader][DAI] -= matched * order.price;
            }

            if (side == Side.BUY) {
                require(traderBalances[msg.sender][DAI] >=  matched * order.price, 'Not enought DAI found late...');
                traderBalances[msg.sender][ticker] += matched;
                traderBalances[msg.sender][DAI] -= matched * order.price;

                traderBalances[order.trader][ticker] -= matched;
                traderBalances[order.trader][DAI] += matched * order.price;
            }

            if (order.filled == order.amount) {
                i = i.add(1);
            }
        }

        uint remove = i.add(1);

        for (uint index = 0; index < orders.length && i < orders.length; index = index.add(1)) {
            // i = 3 entonces queremos borrar los primeros 4 elementos
            orders[index] = orders[i + 1];
            i = i.add(1);
        }

        for (uint index = 0; index < remove; index = index.add(1)) {
            orders.pop();
        }


    }

    modifier hasEnoughtBalance(bytes32 ticker, uint amount, uint price, Side side) {
        if (side == Side.SELL) {
            require(traderBalances[msg.sender][ticker] >= amount, 'Not enought balance');
        } else {
            require(traderBalances[msg.sender][DAI] >= amount.mul(price), 'Not enought DAI');
        }
        _;
    }

    modifier hasEnoughtMarketBalance(bytes32 ticker, uint amount, Side side) {
        if (side == Side.SELL) {
            require(traderBalances[msg.sender][ticker] >= amount, 'Not enought balance');
        } else {
            uint amountToPay;
            uint tokensToBuy;
            Order[] memory orders = orderBook[ticker][uint(Side.SELL)];

            for (uint i = 0; tokensToBuy < amount; i++) {
                if (orders[i].amount + tokensToBuy >= amount) {
                    amountToPay += (amount - tokensToBuy) * orders[i].price;
                    tokensToBuy = amount;
                    break;
                } else {
                    amountToPay += orders[i].amount + orders[i].price;
                    tokensToBuy += orders[i].amount;
                }
                
            }

            require(traderBalances[msg.sender][DAI] >= amountToPay, 'Not enought DAI');
        }
        _;
    }

    modifier tokenIsNotDai(bytes32 ticker) {
        require(ticker != DAI, 'Cannot trade DAI');
        _;
    }

    modifier tokenExists(bytes32 ticker) {
        require(tokens[ticker].tokenAddress != address(0), 'This token doesnt exist');
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin is allowed to do that');
        _;
    }
}