//
// Copyright (C) 2026 Nethesis S.r.l.
// SPDX-License-Identifier: GPL-3.0-or-later
//

import to from "await-to-js";

// Runs a module action with the usual events: completed, aborted and validation-failed.
// Needs the TaskService and UtilService mixins and the "core" and "instanceName" state.
export default {
  methods: {
    async runModuleTask({
      // Another instance, like the hub a node joins
      instance,
      action,
      data,
      title,
      description,
      isNotificationHidden = true,
      completed,
      aborted,
      validationFailed,
      failed,
    }) {
      const eventId = this.getUuid();
      const root = this.core.$root;
      const events = {
        aborted: `${action}-aborted-${eventId}`,
        completed: `${action}-completed-${eventId}`,
        validationFailed: `${action}-validation-failed-${eventId}`,
      };
      // Only one of these events fires: drop the others, or they stay on the shell root
      // and keep this component alive after it is destroyed
      const handlers = {};
      const once = (event, handler) => {
        handlers[event] = (...args) => {
          for (const name of Object.keys(handlers)) {
            root.$off(events[name], handlers[name]);
          }
          handler(...args);
        };
        root.$on(events[event], handlers[event]);
      };
      once("aborted", (taskResult, taskContext) => {
        console.error(`${taskContext.action} aborted`, taskResult);
        aborted(this.$t("error.generic_error"));
      });
      once("completed", (taskContext, taskResult) =>
        completed(taskResult.output)
      );
      if (validationFailed) {
        once("validationFailed", validationFailed);
      }
      const extra = {
        title: title || this.$t("action." + action),
        isNotificationHidden,
        eventId,
      };
      if (description) {
        extra.description = description;
      }
      const task = { action, extra };
      if (data) {
        task.data = data;
      }
      const res = await to(
        this.createModuleTaskForApp(instance || this.instanceName, task)
      );
      if (res[0]) {
        console.error(`error creating task ${action}`, res[0]);
        failed(this.getErrorMessage(res[0]));
      }
    },
  },
};
