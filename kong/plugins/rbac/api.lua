---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by dyson.
--- DateTime: 2018/4/3 下午5:13
---

local crud = require "kong.api.crud_helpers"

return {
  ["/rbac/resources"] = {
    --before = function(self, dao_factory, helpers)
    --  --crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    --  --self.params.consumer_id = self.consumer.id
    --end,

    GET = function(self, dao_factory)
      --return 'hello world'
      crud.paginated_set(self, dao_factory.rbac_resources)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_resources)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_resources)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.params, dao_factory.rbac_resources)
    end
  },

  ["/rbac/roles"] = {
    before = function(self, dao_factory, helpers)
      --crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      --self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_roles)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_roles)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_roles)
    end
  },
  ["/rbac/roles/:role_name_or_id/resources"] = {
    before = function(self, dao_factory, helpers)
      local roles, err = crud.find_by_id_or_field(
        dao_factory.rbac_roles,
        {},
        self.params.role_name_or_id,
        "name"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(roles) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.role_name_or_id = nil
      self.params.role_id = roles[1].id
      self.role = roles[1]
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_role_resources)
    end,
    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_role_resources)
    end,
    DELETE = function(self, dao_factory, helpers)
      local role_resources = dao_factory.rbac_role_resources:find_all(self.params)
      if table.getn(role_resources) <= 0 then
        return helpers.responses.send_HTTP_NOT_FOUND("No resources found.")
      end
      for i = 1, #role_resources do
        crud.delete(role_resources[i], dao_factory.rbac_role_resources)
      end
    end
  },
  ["/rbac/role/:role_name_or_id/consumers"] = {
    before = function(self, dao_factory, helpers)
      local roles, err = crud.find_by_id_or_field(
        dao_factory.rbac_roles,
        {},
        self.params.role_name_or_id,
        "name"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(roles) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND()
      end

      self.params.role_name_or_id = nil
      self.params.role_id = roles[1].id
      self.role = roles[1]
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_role_consumers)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_role_consumers)
    end,
    DELETE = function(self, dao_factory)
      local role_consumers = dao_factory.rbac_role_consumers:find_all(self.params)
      --local primary_keys = {}
      if table.getn(role_consumers) >= 0 then
        return helpers.responses.send_HTTP_NOT_FOUND("No consumers found.")
      end
      for i = 1, #role_consumers do
        crud.delete(role_consumers[i], dao_factory.rbac_role_consumers)
      end
    end
  },
  ["/consumers/:username_or_id/rbac-credentials/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
      self.params.consumer_id = self.consumer.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_credentials)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.rbac_credentials)
    end,

    POST = function(self, dao_factory)
      crud.post(self.params, dao_factory.rbac_credentials)
    end
  },
  ["/rbac/credentials"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.rbac_credentials)
    end,

    POST = function(self, dao_factory, helpers)
      if not self.params.consumer_id then
        if self.params.custom_id or self.params.username then
          local filter = {}
          filter[self.params.custom_id and 'custom_id' or 'username'] = self.params.custom_id and self.params.custom_id or self.params.username
          local consumer
          local consumers, err = dao_factory.consumers:find_all(filter)
          if err then
            return helpers.responses.send_HTTP_BAD_REQUEST(err.message)
          elseif next(consumers) == nil then
            consumer = dao_factory.consumers:insert({ custom_id = self.params.custom_id, username = self.params.username })
          else
            consumer = consumers[1]
          end
          self.params.consumer_id = consumer.id
        end
      end
      self.params.username = nil
      self.params.custom_id = nil
      crud.post(self.params, dao_factory.rbac_credentials)
    end
  },
  ["/rbac/credentials/:credential_key_or_id"] = {
    before = function(self, dao_factory, helpers)
      local credentials, err = crud.find_by_id_or_field(
        dao_factory.rbac_credentials,
        {},
        self.params.credential_key_or_id,
        "key"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND('No credentials found.')
      end

      self.params.credential_key_or_id = nil
      self.params.id = credentials[1].id
      self.credential = credentials[1]
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.credential)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.credential, dao_factory.rbac_credentials)
    end
  },
  ["/rbac/credentials/:credential_key_or_id/consumer"] = {
    before = function(self, dao_factory, helpers)
      local credentials, err = crud.find_by_id_or_field(
        dao_factory.rbac_credentials,
        {},
        self.params.credential_key_or_id,
        "key"
      )

      if err then
        return helpers.yield_error(err)
      elseif next(credentials) == nil then
        return helpers.responses.send_HTTP_NOT_FOUND('No credentials found.')
      end

      self.params.credential_key_or_id = nil
      self.params.username_or_id = credentials[1].consumer_id
      crud.find_consumer_by_username_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.consumer)
    end
  }
}