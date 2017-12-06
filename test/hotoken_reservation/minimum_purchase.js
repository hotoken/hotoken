const {expect} = require('chai')
const HotokenReservation = artifacts.require('./HotokenReservation')

contract('HotokenReservation set minimum purchase', function(accounts) {
  let hotoken
  
  beforeEach(async function() {
    hotoken = await HotokenReservation.new()
  })

  it('should have initial value for minimum purchase', async function() {
    const initialMinimum = (await hotoken.getMinimumPurchase()).toNumber()
    expect(initialMinimum).to.be.equal(300)
  })

  it('should be able to set minimum purchase value', async function() {
    const newMinimumPurchase = 10000
    await hotoken.setMinimumPurchase(newMinimumPurchase)

    const currentMinimum = (await hotoken.getMinimumPurchase()).toNumber()
    expect(currentMinimum).to.be.equal(newMinimumPurchase)
  })

  it('should not be able to set minimum purchase value if not call by owner contract', async function() {
    const user1 = accounts[1]
    const currentMinimumPurchase = (await hotoken.getMinimumPurchase()).toNumber()
    const newMinimumPurchase = 200
    try {
      await hotoken.setMinimumPurchase(newMinimumPurchase, {from: user1})
    } catch (e) {
      expect(e.toString()).to.be.include('revert')
    }

    const AfterMinimum = (await hotoken.getMinimumPurchase()).toNumber()
    expect(AfterMinimum).to.be.equal(currentMinimumPurchase)
  })
})