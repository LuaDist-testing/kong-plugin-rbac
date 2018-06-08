local utils = require "kong.tools.utils"

local function default_key_names(t)
  if not t.key_names then
    return { "api_key", "x-token" }
  end
end

local function check_keys(keys)
  for _, key in ipairs(keys) do
    local res, err = utils.validate_header_name(key, false)

    if not res then
      return false, "'" .. key .. "' is illegal: " .. err
    end
  end

  return true
end

local function check_user(anonymous)
  if anonymous == "" or utils.is_valid_uuid(anonymous) then
    return true
  end

  return false, "the anonymous user must be empty or a valid uuid"
end

return {
  no_consumer = true,
  fields = {
    -- Describe your plugin's configuration's schema here.
    key_names = {
      required = true,
      type = "array",
      default = default_key_names,
      func = check_keys,
    },
    hide_credentials = {
      type = "boolean",
      default = false,
    },
    anonymous = {
      type = "string",
      default = "",
      func = check_user,
    },
    key_in_header = {
      type = "boolean",
      default = true,
    },
    key_in_query = {
      type = "boolean",
      default = false,
    },
    key_in_body = {
      type = "boolean",
      default = false,
    },
    run_on_preflight = {
      type = "boolean",
      default = true,
    },
    rbac_enabled = {
      type = "boolean",
      default = true
    }
  },
  self_check = function(schema, plugin_t, dao, is_updating)
    -- perform any custom verification
    return true
  end
}
