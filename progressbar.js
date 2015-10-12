"use strict";

const _ = require("lodash")
const colors = require("colors")

const symbols = [
  "\u258F", // ▏	Left one eighth block
  "\u258E",	// ▎	Left one quarter block
  "\u258D",	// ▍	Left three eighths block
  "\u258C",	// ▌	Left half block
  "\u258B",	// ▋	Left five eighths block
  "\u258A", // ▊	Left three quarters block
  "\u2589", // ▉	Left seven eighths block
  "\u2588"  // █	Full block
]

const defaultOptions = {
  barWidth: 50
}

class ProgressBar {
  constructor(total, options) {
    this._total = total
    this._current = 0
    this.options = _.merge(defaultOptions, options || {})
  }

  draw() {
    const ratio = this.percentDone
    const scaled = ratio * this.options.barWidth
    const full = Math.floor(scaled)
    const partial = scaled - full

    const filled = Array(full + 1).join(symbols.slice(-1))
    const tail = symbols[Math.floor(partial * symbols.length) - 1] || ''
    const padding = Array(this.options.barWidth - full - tail.length + 1).join(" ")

    function countSymbols(string) { return [...string].length }
    function doDraw(s) { process.stdout.write(s + Array(process.stdout.columns - countSymbols(s)).join(" ") + "\r") }

    doDraw(
      (this.options.caption ? this.options.caption + " " : '') +
        `${filled}${tail}${padding}`.green.bgBlack +
        ` ${this._current}/${this._total} ${this.remaining/1000}s`)
  }

  tick() {
    if (!this._startTime) this.start()
    this._current++
    this.complete = this._current >= this._total
    this.draw()
    if (this.complete) this.finish()
  }

  start() { this._startTime = new Date().getTime() }
  finish() { process.stdout.write("\n") }
  get percentDone() { return this._current/this._total }
  get elapsed() { return (new Date().getTime()) - this._startTime }
  get remaining() { return (this.elapsed / this.percentDone) - this.elapsed }
}

// const progress = new ProgressBar(100, {barWidth: 20})

// const timer = setInterval(function () {
//   progress.tick();
//   if (progress.complete) {
//     console.log('\ncomplete\n');
//     clearInterval(timer);
//   }
// }, 20);

module.exports = ProgressBar
