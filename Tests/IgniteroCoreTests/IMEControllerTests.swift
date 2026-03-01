import Testing

@testable import IgniteroCore

@Suite("IMEController")
struct IMEControllerTests {

  @Test func canBeCreated() {
    let controller = IMEController()
    #expect(controller is IMEController)
  }

  @Test func switchToASCIIDoesNotCrash() {
    let controller = IMEController()
    controller.switchToASCII()
  }

  @Test func conformsToIMEControlling() {
    let controller: any IMEControlling = IMEController()
    controller.switchToASCII()
  }
}
