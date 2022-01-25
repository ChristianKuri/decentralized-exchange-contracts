const Dai = artifacts.require('Dai');
const Bat = artifacts.require('Bat');
const Rep = artifacts.require('Rep');
const Zrx = artifacts.require('Zrx');
const Dex = artifacts.require('Dex');

const [DAI, BAT, REP, ZRX] = ['DAI', 'BAT', 'REP', 'ZRX'].map(ticker => web3.utils.fromAscii(ticker));

const SIDE = {
    BUY: 0,
    SELL: 1
};

module.exports = async function (deployer, _network, accounts) {
    const [trader1, trader2, trader3, trader4, _] = accounts;

    await Promise.all(
        [Dai, Bat, Rep, Zrx, Dex].map(contract => deployer.deploy(contract))
    );

    const [dai, bat, rep, zrx, dex] = await Promise.all(
        [Dai, Bat, Rep, Zrx, Dex].map(contract => contract.deployed())
    );

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

            const ticker = await token.symbol();
            await dex.deposit(amount, web3.utils.fromAscii(ticker), { from: trader })
        }
    }

    await Promise.all([dai, bat, rep, zrx].map(token => seedTokenBalance(token, [trader1, trader2, trader3, trader4])));
}