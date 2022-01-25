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
    mapping(address => mapping (bytes32 => uint)) public traderLockedBalances;
    mapping(bytes32 => mapping(uint => Order[])) public orderBook;

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

    function getOrder(uint id) external view returns(Order memory) {
        return orderList[id];
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
        Order memory createdOrder = Order(orderList.length, msg.sender, side, ticker, amount, 0, price, block.timestamp);
        Order[] storage orders = orderBook[ticker][uint(side)];
        orderList.push(createdOrder);
        orders.push(createdOrder);

        for (uint i = orders.length > 0 ? orders.length - 1 : 0; i > 0; i = i.sub(1)) {
            if(side == Side.BUY && orders[i - 1].price > orders[i].price) {
                break;   
            }
            if(side == Side.SELL && orders[i - 1].price < orders[i].price) {
                break;   
            }
            Order memory order = orders[i - 1];
            orders[i - 1] = orders[i];
            orders[i] = order;
        }

        if (side == Side.SELL) {
            traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(amount);
            traderLockedBalances[msg.sender][ticker] = traderLockedBalances[msg.sender][ticker].add(amount);
        }

        if (side == Side.BUY) {
            traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI].sub(amount.mul(price));
            traderLockedBalances[msg.sender][DAI] = traderLockedBalances[msg.sender][DAI].add(amount.mul(price));
        }
    }

    function createMarketOrder(
        bytes32 ticker,
        uint amount,
        Side side)
        tokenExists(ticker)
        tokenIsNotDai(ticker)
        external {
        if(side == Side.SELL) {
            require(
                traderBalances[msg.sender][ticker] >= amount, 
                'token balance too low'
            );
        }
        Order[] storage orders = orderBook[ticker][uint(side == Side.BUY ? Side.SELL : Side.BUY)];
        uint i;
        uint remaining = amount;
        
        while(i < orders.length && remaining > 0) {
            uint available = orders[i].amount.sub(orders[i].filled);
            uint matched = (remaining > available) ? available : remaining;
            remaining = remaining.sub(matched);
            orders[i].filled = orders[i].filled.add(matched);
            emit NewTrade(
                orderList.length,
                orders[i].id,
                ticker,
                orders[i].trader,
                msg.sender,
                matched,
                orders[i].price,
                block.timestamp
            );
            if(side == Side.SELL) {
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(matched);
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI].add(matched.mul(orders[i].price));
                traderBalances[orders[i].trader][ticker] = traderBalances[orders[i].trader][ticker].add(matched);
                traderLockedBalances[orders[i].trader][DAI] = traderLockedBalances[orders[i].trader][DAI].sub(matched.mul(orders[i].price));
            }
            if(side == Side.BUY) {
                require(
                    traderBalances[msg.sender][DAI] >= matched.mul(orders[i].price),
                    'dai balance too low'
                );
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(matched);
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI].sub(matched.mul(orders[i].price));
                traderLockedBalances[orders[i].trader][ticker] = traderLockedBalances[orders[i].trader][ticker].sub(matched);
                traderBalances[orders[i].trader][DAI] = traderBalances[orders[i].trader][DAI].add(matched.mul(orders[i].price));
            }
            i++;
        }
        
        i = 0;
        while(i < orders.length && orders[i].filled == orders[i].amount) {
            for(uint j = i; j < orders.length - 1; j++ ) {
                orders[j] = orders[j + 1];
            }
            orders.pop();
            i++;
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