local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local singletons = require "kong.singletons"
local public_tools = require "kong.tools.public"
local BasePlugin = require "kong.plugins.base_plugin"
local _ = require "lodash"
local router = require "router"

local ngx_set_header = ngx.req.set_header
local ngx_get_headers = ngx.req.get_headers
local set_uri_args = ngx.req.set_uri_args
local get_uri_args = ngx.req.get_uri_args
local clear_header = ngx.req.clear_header
local ngx_req_read_body = ngx.req.read_body
local ngx_req_set_body_data = ngx.req.set_body_data
local ngx_encode_args = ngx.encode_args
local get_method = ngx.req.get_method
local type = type

-- local _realm = 'Key realm="' .. _KONG._NAME .. '"'
local _realm = 'Key realm="RBAC"'

local RBACAuthHandler = BasePlugin:extend()

RBACAuthHandler.PRIORITY = 1003
RBACAuthHandler.VERSION = "0.1.0"

function RBACAuthHandler:new()
  RBACAuthHandler.super.new(self, "rbac")
end

local function load_credential(key)
  local creds, err = singletons.dao.rbac_credentials:find_all {
    key = key
  }
  if not creds then
    return nil, err
  end
  return creds[1]
end

local function load_consumer(consumer_id, anonymous)
  local result, err = singletons.dao.consumers:find { id = consumer_id }
  if not result then
    if anonymous and not err then
      err = 'anonymous consumer "' .. consumer_id .. '" not found'
    end
    return nil, err
  end
  return result
end
local function load_api_resources(api_id)
  local cache = singletons.cache
  local dao = singletons.dao
  local resources_cache_key = dao.rbac_resources:cache_key(api_id)
  local resources, err = cache:get(resources_cache_key, nil, (function(id)
    return dao.rbac_resources:find_all({ api_id = id })
  end), api_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  return resources
end
local function load_consumer_resources(consumer_id)
  local cache = singletons.cache
  local dao = singletons.dao
  local role_cache_key = dao.rbac_role_consumers:cache_key(consumer_id)
  local roles, err = cache:get(role_cache_key, nil, (function(id)
    return dao.rbac_role_consumers:find_all({ consumer_id = id })
  end), consumer_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end
  if table.getn(roles) < 1 then
    return {}
  end
  local resources = {}
  _.forEach(roles, (function(role)
    local role_resource_cache_key = dao.rbac_role_resources:cache_key(role.role_id)
    local role_resources, role_resource_err = cache:get(role_resource_cache_key, nil, (function(role_id)
      return dao.rbac_role_resources:find_all({ role_id = role_id })
    end), role.role_id)
    if role_resource_err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(role_resource_err)
    end
    resources = _.union(resources, role_resources)
  end))
  return resources
end

local function set_consumer(consumer, credential)
  ngx_set_header(constants.HEADERS.CONSUMER_ID, consumer.id)
  ngx_set_header(constants.HEADERS.CONSUMER_CUSTOM_ID, consumer.custom_id)
  ngx_set_header(constants.HEADERS.CONSUMER_USERNAME, consumer.username)
  ngx.ctx.authenticated_consumer = consumer
  if credential then
    ngx_set_header(constants.HEADERS.CREDENTIAL_USERNAME, credential.username)
    ngx.ctx.authenticated_credential = credential
    ngx_set_header(constants.HEADERS.ANONYMOUS, nil) -- in case of auth plugins concatenation
  else
    ngx_set_header(constants.HEADERS.ANONYMOUS, true)
  end

end
local function do_rbac(consumer, api)
  local api_resources = load_api_resources(api.id)
  if table.getn(api_resources) < 1 then
    return true
  end
  local consumer_resources = load_consumer_resources(consumer.id)
  local r = router.new()
  local ok = false
  local matched_protected_resource = false
  _.forEach(api_resources, (function(resource)
    r:match(string.upper(resource.method), resource.upstream_path, function()
      _.forEach(consumer_resources, (function(consumer_resource)
        matched_protected_resource = true
        ok = consumer_resource.resource_id == resource.id
      end))
    end)
  end))
  r:execute(get_method(), string.sub(ngx.var.uri, string.len(ngx.ctx.router_matches.uri) + 1))
  if not matched_protected_resource then
    ok = true
  end
  return ok
end
local function do_authentication(conf)
  if type(conf.key_names) ~= "table" then
    ngx.log(ngx.ERR, "[rbac] no conf.key_names set, aborting plugin execution")
    return false, { status = 500, message = "Invalid plugin configuration" }
  end

  local key
  local headers = ngx_get_headers()
  local uri_args = get_uri_args()
  local body_data

  -- read in the body if we want to examine POST args
  if conf.key_in_body then
    ngx_req_read_body()
    body_data = public_tools.get_body_args()
  end

  -- search in headers & querystring
  for i = 1, #conf.key_names do
    local name = conf.key_names[i]
    local v
    if conf.key_in_header then
      v = headers[name]
    end
    if not v and conf.key_in_query then
      -- search in querystring
      v = uri_args[name]
    end

    -- search the body, if we asked to
    if not v and conf.key_in_body then
      v = body_data[name]
    end

    if type(v) == "string" then
      key = v
      if conf.hide_credentials then
        uri_args[name] = nil
        set_uri_args(uri_args)
        clear_header(name)

        if conf.key_in_body then
          body_data[name] = nil
          ngx_req_set_body_data(ngx_encode_args(body_data))
        end
      end
      break
    elseif type(v) == "table" then
      -- duplicate API key, HTTP 401
      return false, { status = 401, message = "Duplicate API key found" }
    end
  end

  -- this request is missing an API key, HTTP 401
  if not key then
    ngx.header["WWW-Authenticate"] = _realm
    return false, { status = 401, message = "No API key found in request" }
  end

  local cache = singletons.cache
  local dao = singletons.dao

  local credential_cache_key = dao.rbac_credentials:cache_key(key)
  local credential, credential_err = cache:get(credential_cache_key, nil,
    load_credential, key)
  if credential_err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(credential_err)
  end

  -- no credential in DB, for this key, it is invalid, HTTP 403
  if not credential then
    return false, { status = 403, message = "Invalid authentication credentials" }
  end

  -- credential expired.
  if credential.expired_at and credential.expired_at <= (os.time() * 1000) then
    return false, { status = 403, message = "Invalid authentication credentials" }
  end
  -----------------------------------------
  -- Success, this request is authenticated
  -----------------------------------------

  -- retrieve the consumer linked to this API key, to set appropriate headers

  local consumer_cache_key = dao.consumers:cache_key(credential.consumer_id)
  local consumer, err = cache:get(consumer_cache_key, nil, load_consumer,
    credential.consumer_id)
  if err then
    return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  set_consumer(consumer, credential)

  return consumer
end

function RBACAuthHandler:access(conf)
  RBACAuthHandler.super.access(self)

  -- check if preflight request and whether it should be authenticated
  if not conf.run_on_preflight and get_method() == "OPTIONS" then
    return
  end

  if ngx.ctx.authenticated_credential and conf.anonymous ~= "" then
    -- we're already authenticated, and we're configured for using anonymous,
    -- hence we're in a logical OR between auth methods and we're already done.
    return
  end

  local consumer, err = do_authentication(conf)
  if not consumer then
    if conf.anonymous ~= "" then
      -- get anonymous user
      local consumer_cache_key = singletons.dao.consumers:cache_key(conf.anonymous)
      local anonymous_err
      consumer, anonymous_err = singletons.cache:get(consumer_cache_key, nil,
        load_consumer,
        conf.anonymous, true)
      if anonymous_err then
        responses.send_HTTP_INTERNAL_SERVER_ERROR(anonymous_err)
      end
      set_consumer(consumer, nil)
    else
      return responses.send(err.status, err.message)
    end
  end
  if conf.rbac_enabled and consumer then
    local ok, rbac_err = do_rbac(consumer, ngx.ctx.api)
    if rbac_err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(rbac_err)
    end
    if not ok then
      return responses.send_HTTP_FORBIDDEN('Access denied.')
    end
  end
end

return RBACAuthHandler
