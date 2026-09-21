import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "output"]

  connect() {
    this.update()
  }

  update() {
    const input = this.inputTarget
    this.outputTarget.textContent = input.value
    const progress = (Number(input.value) - Number(input.min)) / (Number(input.max) - Number(input.min)) * 100
    input.style.setProperty("--progress", `${progress}%`)
  }
}
