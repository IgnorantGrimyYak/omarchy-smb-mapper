.pragma library

function parseOutput(text) {
  try {
    return JSON.parse(String(text || ""))
  } catch (e) {
    return null
  }
}

function plainText(value, fallback) {
  var text = String(value == null ? "" : value)
  text = text.replace(/[\x00-\x1F\x7F<>`]/g, "")
  text = text.replace(/\\/g, "")
  text = text.replace(/\s+/g, " ").trim()
  if (text.length > 160)
    text = text.slice(0, 157) + "..."
  return text || (fallback || "")
}

function sanitizeShareName(value) {
  var raw = String(value == null ? "" : value).trim()
  if (!raw || raw === "." || raw === "..")
    return ""
  if (/[\\/:*?"<>|\x00-\x1F]/.test(raw))
    return ""
  var text = plainText(raw, "")
  return text && text.length <= 80 ? text : ""
}

function sanitizeBrowseList(names) {
  var out = []
  var seen = {}
  var list = names || []
  for (var i = 0; i < list.length && out.length < 32; i++) {
    var name = sanitizeShareName(list[i])
    if (!name || seen[name])
      continue
    seen[name] = true
    out.push(name)
  }
  return out
}

function processError(text, fallback) {
  var parsed = parseOutput(text)
  if (parsed && parsed.error)
    return plainText(parsed.error, fallback)
  return plainText(String(text || "").trim(), fallback)
}

function helperPathFromUrl(url) {
  return String(url || "").replace(/^file:\/\//, "")
}

function mountedCount(shares) {
  var count = 0
  var list = shares || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].mounted)
      count += 1
  }
  return count
}

function statusLabel(share, busyId, busyKind, failure) {
  if (!share)
    return ""
  if (failure && failure.id === share.id)
    return plainText(failure.message, "Failed")
  if (busyId === share.id) {
    if (busyKind === "mount")
      return "Connecting…"
    if (busyKind === "unmount")
      return "Disconnecting…"
    if (busyKind === "remove")
      return "Removing…"
  }
  if (share.mounted)
    return "Mounted"
  if (!share.guest && share.hasSecret === false)
    return "Password needed"
  return "Ready"
}

function barIcon(mounted) {
  return mounted > 0 ? "󰉌" : "󰉍"
}

function barTooltip(mounted, total) {
  if (total <= 0)
    return "SMB Drives"
  if (mounted <= 0)
    return "SMB Drives · none connected"
  if (mounted === 1)
    return "SMB Drives · 1 connected"
  return "SMB Drives · " + mounted + " connected"
}

function heroMeta(mounted, total) {
  if (total <= 0)
    return "NO SHARES YET"
  if (mounted <= 0)
    return "NOT CONNECTED"
  if (mounted === total)
    return "ALL CONNECTED"
  return mounted + " OF " + total + " CONNECTED"
}

function shareSubtitle(share) {
  if (!share)
    return ""
  return "//" + plainText(share.host, "server") + "/" + plainText(share.share, "share")
}

function emptyForm() {
  return {
    id: "",
    label: "",
    host: "",
    share: "",
    username: "",
    domain: "",
    password: "",
    guest: false,
    automount: true,
    savePassword: true
  }
}

function cloneForm(form) {
  var next = emptyForm()
  var source = form || emptyForm()
  next.id = source.id || ""
  next.label = source.label || ""
  next.host = source.host || ""
  next.share = source.share || ""
  next.username = source.username || ""
  next.domain = source.domain || ""
  next.password = source.password || ""
  next.guest = !!source.guest
  next.automount = source.automount !== false
  next.savePassword = source.savePassword !== false
  return next
}

function setFormField(form, key, value) {
  var next = cloneForm(form)
  next[key] = value
  return next
}

function formFromShare(share) {
  var form = emptyForm()
  if (!share)
    return form
  form.id = share.id || ""
  form.label = share.label || ""
  form.host = share.host || ""
  form.share = share.share || ""
  form.username = share.username || ""
  form.domain = share.domain || ""
  form.guest = !!share.guest
  form.automount = !!share.automount
  form.savePassword = false
  form.password = ""
  return form
}

function requestPayload(form) {
  var payload = {
    label: String(form.label || "").trim(),
    host: String(form.host || "").trim(),
    share: String(form.share || "").trim(),
    username: form.guest ? "" : String(form.username || "").trim(),
    domain: form.guest ? "" : String(form.domain || "").trim(),
    guest: !!form.guest,
    automount: !!form.automount
  }
  if (form.password)
    payload.password = String(form.password)
  if (form.savePassword)
    payload.savePassword = true
  return payload
}

function doctorHint(doctor) {
  if (!doctor)
    return ""
  var missing = []
  if (!doctor.gio)
    missing.push("gio")
  if (!doctor.gvfsSmb)
    missing.push("gvfs-smb")
  if (!doctor.secretTool)
    missing.push("secret-tool")
  if (!doctor.pythonGobject)
    missing.push("python-gobject")
  if (missing.length === 0)
    return doctor.keyring ? "" : "Unlock your system keyring to save passwords."
  return "Install " + missing.join(", ") + " to map SMB drives."
}
