const fs = require("fs")
const path = require("path")
const vm = require("vm")
const assert = require("assert")

const source = fs.readFileSync(path.join(__dirname, "../Model.js"), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const context = { JSON, Math, Number, String, Array, Object }
vm.createContext(context)
vm.runInContext(source, context)

assert.strictEqual(context.mountedCount([{ mounted: true }, { mounted: false }, { mounted: true }]), 2)
assert.strictEqual(context.barIcon(0), "󰉍")
assert.strictEqual(context.barIcon(1), "󰉌")
assert.strictEqual(context.heroMeta(0, 0), "NO SHARES YET")
assert.strictEqual(context.heroMeta(1, 2), "1 OF 2 CONNECTED")
assert.strictEqual(context.shareSubtitle({ host: "nas.local", share: "media" }), "//nas.local/media")
assert.strictEqual(
  context.statusLabel({ id: "a", mounted: true }, "", "", { id: "", message: "" }),
  "Mounted"
)
assert.strictEqual(
  context.statusLabel({ id: "a" }, "a", "mount", { id: "", message: "" }),
  "Connecting…"
)
assert.strictEqual(
  context.processError('{"ok":false,"error":"bad host"}', "fallback"),
  "bad host"
)

const payload = context.requestPayload({
  label: " NAS ",
  host: "nas.local",
  share: "media",
  username: "bryan",
  domain: "",
  guest: false,
  automount: true,
  password: "secret",
  savePassword: true
})
assert.strictEqual(payload.host, "nas.local")
assert.strictEqual(payload.password, "secret")
assert.ok(!("password" in context.requestPayload({ host: "nas", share: "x", guest: true })))

const next = context.setFormField(context.emptyForm(), "host", "files.example")
assert.strictEqual(next.host, "files.example")
assert.strictEqual(context.emptyForm().host, "")

assert.match(context.doctorHint({ gio: false, gvfsSmb: true, secretTool: true, pythonGobject: true, keyring: true }), /gio/)
assert.strictEqual(context.doctorHint({ gio: true, gvfsSmb: true, secretTool: true, pythonGobject: true, keyring: true }), "")

console.log("model tests passed")
