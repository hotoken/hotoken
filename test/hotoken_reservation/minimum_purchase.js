const {expect} = require('chai')
const HotokenReservation = artifacts.require('./HotokenReservation')

contract('HotokenReservation', function(accounts) {
  describe('minimumPurchase', function() {
    it('should set the default minimum as $300', async function() {
      const h = await HotokenReservation.deployed()
      let min = await h.minimumPurchase.call()
      expect(min.toNumber()).to.be.equal(300 * 10 ** 18)
    })
  })
  describe('setMinimumPurchase', function() {
    it('should set the minimum purchase value', async function() {
      const h = await HotokenReservation.deployed()
      let min = 450
      await h.setMinimumPurchase(min)
      let contractMin = await h.minimumPurchase.call()
      expect(contractMin.toNumber()).to.be.equal(450 * 10 ** 18)
    })
    it('should not be able to set minimum purchase value if not call by owner contract', async function() {
      const h = await HotokenReservation.deployed()
      const user1 = accounts[1]
      const current = await h.minimumPurchase.call()
      const newMin = 200
      try {
        await h.setMinimumPurchase(newMin, {from: user1})
        expect.fail(true, false, 'Operation should be reverted')
      } catch (e) {
        expect(e.toString()).to.be.include('revert')
      }

      const after = await h.minimumPurchase.call()
      expect(after.toNumber()).to.be.equal(current.toNumber())
    })
  })
})
