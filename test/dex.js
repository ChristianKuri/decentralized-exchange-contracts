const { expectRevert } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');
const Dai = artifacts.require('Dai');
const Bat = artifacts.require('Bat');
const Rep = artifacts.require('Rep');
const Zrx = artifacts.require('Zrx');
const Dex = artifacts.require('Dex');


contract('Dex', (accounts) => {
    let dai, bat, rep, zrx, dex;
    const [trader1, trader2] = [accounts[1], accounts[2]];
    const [DAI, BAT, REP, ZRX] = ['DAI', 'BAT', 'REP', 'ZRX'].map(ticker => web3.utils.fromAscii(ticker));

    const SIDE = {
        BUY: 0,
        SELL: 1
    }

    beforeEach(async () => {
        [dai, bat, rep, zrx, dex] = await Promise.all([
            Dai.new(),
            Bat.new(),
            Rep.new(),
            Zrx.new(),
            Dex.new()
        ]);

        await Promise.all([
            dex.addToken(DAI, dai.address),
            dex.addToken(BAT, bat.address),
            dex.addToken(REP, rep.address),
            dex.addToken(ZRX, zrx.address),
        ]);

        const amount = web3.utils.toWei('1000');

        const seedTokenBalance = async (token, traders) => {
            for (let index = 0; index < traders.length; index++) {
                const trader = traders[index];
                await token.faucet(trader, amount);
                await token.approve(dex.address, amount, { from: trader })
            }
        }

        await Promise.all([dai, bat, rep, zrx].map(token => seedTokenBalance(token, [trader1, trader2])));
    });

    it('allows to deposit tokens', async () => {
        const amount = web3.utils.toWei('100');

        await dex.deposit(amount, DAI, { from: trader1 });

        const balance = await dex.traderBalances(trader1, DAI);

        assert(balance.toString() === amount);
    });

    it('doesnt allow you to deposit a token that is not included in the list', async () => {
        await expectRevert(dex.deposit(web3.utils.toWei('100'), web3.utils.fromAscii('TOKEN'), { from: trader1 }), 'This token doesnt exist')
    });

    it('allows to withdraw tokens', async () => {
        const amount = web3.utils.toWei('100');
        await dex.deposit(amount, DAI, { from: trader1 });
        await dex.withdraw(amount, DAI, { from: trader1 });

        const [balanceDex, balanceDai] = await Promise.all([
            dex.traderBalances(trader1, DAI),
            dai.balanceOf(trader1)
        ]);

        assert(balanceDex.isZero());
        assert(balanceDai.toString() === web3.utils.toWei('1000'));
    });

    it('doesnt allow to withdraw tokens that are not in the list', async () => {
        await expectRevert(
            dex.withdraw(web3.utils.toWei('100'), web3.utils.fromAscii('TOKEN'), { from: trader1 }),
            'This token doesnt exist'
        );
    });

    it('verifies that account has enought balance to withdraw', async () => {
        await dex.deposit(web3.utils.toWei('100'), DAI, { from: trader1 });

        await expectRevert(
            dex.withdraw(web3.utils.toWei('1000'), DAI, { from: trader1 }),
            'Not enought balance'
        );
    });

    it('requires a valid token to create a limit order', async () => {
        const TOKEN = web3.utils.fromAscii('TOKEN');
        const amount = web3.utils.toWei('100');
        const price = 1000;

        await expectRevert(
            dex.createLimitOrder(TOKEN, amount, price, SIDE.BUY, { from: trader1 }),
            'This token doesnt exist'
        );
    });

    it('doesnt allow the token to be DAI to create a limit order', async () => {
        const amount = web3.utils.toWei('100');
        const price = 1000;

        await expectRevert(
            dex.createLimitOrder(DAI, amount, price, SIDE.BUY, { from: trader1 }),
            'Cannot trade DAI'
        );
    });

    it('requires to have enought balance to create a sell limit order', async () => {
        const amount = web3.utils.toWei('100');
        const price = 1000;

        await expectRevert(
            dex.createLimitOrder(BAT, amount, price, SIDE.SELL, { from: trader1 }),
            'Not enought balance'
        );
    });

    it('allows to create sell limit orders', async () => {
        const amount = web3.utils.toWei('50');
        const price = 1000;

        await dex.deposit(amount, BAT, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, price, SIDE.SELL, { from: trader1 });

        const buyOrders = await dex.getOrders(BAT, SIDE.BUY);
        const sellOrders = await dex.getOrders(BAT, SIDE.SELL);

        assert(sellOrders.length === 1);
        assert(sellOrders[0].trader === trader1);
        assert(sellOrders[0].ticker === web3.utils.padRight(BAT, 64));
        assert(sellOrders[0].price === price.toString());
        assert(sellOrders[0].amount === amount);
        assert(buyOrders.length === 0);
    });

    it('allows to create sell limit orders and puts them in the correct place', async () => {
        const amount = web3.utils.toWei('50');

        await dex.deposit(web3.utils.toWei('1000'), BAT, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 500, SIDE.SELL, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 200, SIDE.SELL, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 800, SIDE.SELL, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 300, SIDE.SELL, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 100, SIDE.SELL, { from: trader1 });

        const buyOrders = await dex.getOrders(BAT, SIDE.BUY);
        const sellOrders = await dex.getOrders(BAT, SIDE.SELL);

        assert(sellOrders.length === 5);

        assert(sellOrders[0].price === '100');
        assert(sellOrders[1].price === '200');
        assert(sellOrders[2].price === '300');
        assert(sellOrders[3].price === '500');
        assert(sellOrders[4].price === '800');

        assert(buyOrders.length === 0);
    });

    it('only allows to create sell limit orders until the amount of deposited tokens', async () => {
        const amount = web3.utils.toWei('50');

        await dex.deposit(web3.utils.toWei('100'), BAT, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, 500, SIDE.SELL, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 200, SIDE.SELL, { from: trader1 });

        await expectRevert(
            dex.createLimitOrder(BAT, amount, 800, SIDE.SELL, { from: trader1 }),
            'Not enought balance'
        );

        const sellOrders = await dex.getOrders(BAT, SIDE.SELL);
        assert(sellOrders.length === 2);
    });



    it('requires to have DAI balance to create a buy limit order', async () => {
        const amount = web3.utils.toWei('100');
        const price = 1000;

        await expectRevert(
            dex.createLimitOrder(BAT, amount, price, SIDE.BUY, { from: trader1 }),
            'Not enought DAI'
        );
    });

    it('requires to have enought DAI balance to create a buy limit order', async () => {
        const amount = web3.utils.toWei('100');
        const price = 5;

        await dex.deposit(web3.utils.toWei('100'), DAI, { from: trader1 });

        await expectRevert(
            dex.createLimitOrder(BAT, amount, price, SIDE.BUY, { from: trader1 }),
            'Not enought DAI'
        );
    });

    it('allows to create BUY limit orders', async () => {
        const amount = web3.utils.toWei('100');
        const price = 5;

        await dex.deposit(web3.utils.toWei('500'), DAI, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, price, SIDE.BUY, { from: trader1 });

        const buyOrders = await dex.getOrders(BAT, SIDE.BUY);
        const sellOrders = await dex.getOrders(BAT, SIDE.SELL);

        assert(buyOrders.length === 1);
        assert(buyOrders[0].trader === trader1);
        assert(buyOrders[0].ticker === web3.utils.padRight(BAT, 64));
        assert(buyOrders[0].price === price.toString());
        assert(buyOrders[0].amount === amount);
        assert(sellOrders.length === 0);
    });

    it('allows to create BUY limit orders and puts them in the correct place', async () => {
        const amount = web3.utils.toWei('10');

        await dex.deposit(web3.utils.toWei('1000'), DAI, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, 5, SIDE.BUY, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 2, SIDE.BUY, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 8, SIDE.BUY, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 3, SIDE.BUY, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 1, SIDE.BUY, { from: trader1 });

        const buyOrders = await dex.getOrders(BAT, SIDE.BUY);
        const sellOrders = await dex.getOrders(BAT, SIDE.SELL);

        assert(buyOrders.length === 5);

        assert(buyOrders[0].price === '8');
        assert(buyOrders[1].price === '5');
        assert(buyOrders[2].price === '3');
        assert(buyOrders[3].price === '2');
        assert(buyOrders[4].price === '1');

        assert(sellOrders.length === 0);
    });

    it('only allows to create BUY limit orders until the amount of deposited tokens', async () => {
        const amount = web3.utils.toWei('10');

        await dex.deposit(web3.utils.toWei('1000'), DAI, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, 50, SIDE.BUY, { from: trader1 });
        await dex.createLimitOrder(BAT, amount, 20, SIDE.BUY, { from: trader1 });

        await expectRevert(
            dex.createLimitOrder(BAT, amount, 80, SIDE.BUY, { from: trader1 }),
            'Not enought DAI'
        );
    });

    it('does not allow to withdraw locked tockens from sell orders', async () => {
        const amount = web3.utils.toWei('100');

        await dex.deposit(web3.utils.toWei('100'), BAT, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, 500, SIDE.SELL, { from: trader1 });

        await expectRevert(
            dex.withdraw(web3.utils.toWei('100'), BAT, { from: trader1 }),
            'Not enought balance'
        );
    });

    it('does not allow to withdraw locked tockens from buy orders', async () => {
        const amount = web3.utils.toWei('100');

        await dex.deposit(web3.utils.toWei('100'), DAI, { from: trader1 });

        await dex.createLimitOrder(BAT, amount, 1, SIDE.BUY, { from: trader1 });

        await expectRevert(
            dex.withdraw(web3.utils.toWei('100'), DAI, { from: trader1 }),
            'Not enought balance'
        );
    });

    it('it should create market order and match agains existing limit order', async () => {
        const DAI = web3.utils.fromAscii('DAI');

        /** Trader 1 */
        await dex.deposit(web3.utils.toWei('100'), DAI, { from: trader1 });
        await dex.createLimitOrder(BAT, web3.utils.toWei('10'), 10, SIDE.BUY, { from: trader1 });

        /** Trader 2 */
        await dex.deposit(web3.utils.toWei('100'), BAT, { from: trader2 });
        await dex.createMarketOrder(BAT, web3.utils.toWei('5'), SIDE.SELL, { from: trader2 });

        const balances = await Promise.all([
            dex.traderBalances(trader1, DAI),
            dex.traderBalances(trader1, BAT),
            dex.traderLockedBalances(trader1, DAI),
            dex.traderBalances(trader2, DAI),
            dex.traderBalances(trader2, BAT)
        ]);

        const orders = await dex.getOrders(BAT, SIDE.BUY)

        /** Trader 1 */
        assert(orders[0].filled === web3.utils.toWei('5')) // trader 1 limit order was 50% filled (he bought 5 of the 10 BAT that he wanted)
        assert(balances[1].toString() === web3.utils.toWei('5')) // trader 1 BAT balance is now 5
        assert(balances[2].toString() === web3.utils.toWei('50')) // trader 1 DAI balance is 50 and is locked

        /** Trader 2 */
        assert(balances[3].toString() === web3.utils.toWei('50')) // trader 2 has now 50 DAI (he sold 5 BAT)
        assert(balances[4].toString() === web3.utils.toWei('95')) // trader 2 has now 95 BAT
    });

    it('should NOT create market order if token balance too low', async () => {
        await expectRevert(
            dex.createMarketOrder(
                REP,
                web3.utils.toWei('101'),
                SIDE.SELL,
                { from: trader2 }
            ),
            'token balance too low'
        );
    });

    it('should NOT create market order if dai balance too low', async () => {
        await dex.deposit(
            web3.utils.toWei('100'),
            REP,
            { from: trader1 }
        );

        await dex.createLimitOrder(
            REP,
            web3.utils.toWei('100'),
            10,
            SIDE.SELL,
            { from: trader1 }
        );

        await expectRevert(
            dex.createMarketOrder(
                REP,
                web3.utils.toWei('101'),
                SIDE.BUY,
                { from: trader2 }
            ),
            'dai balance too low'
        );
    });

    it('should NOT create market order if token is DAI', async () => {
        await expectRevert(
            dex.createMarketOrder(
                DAI,
                web3.utils.toWei('1000'),
                SIDE.BUY,
                { from: trader1 }
            ),
            'Cannot trade DAI'
        );
    });

    it('should NOT create market order if token does not not exist', async () => {
        await expectRevert(
            dex.createMarketOrder(
                web3.utils.fromAscii('TOKEN-DOES-NOT-EXIST'),
                web3.utils.toWei('1000'),
                SIDE.BUY,
                { from: trader1 }
            ),
            'This token doesnt exist'
        );
    });
});
