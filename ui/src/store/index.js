//
// Copyright (C) 2026 Nethesis S.r.l.
// SPDX-License-Identifier: GPL-3.0-or-later
//
import Vue from "vue";
import Vuex from "vuex";

Vue.use(Vuex);

export default new Vuex.Store({
  state: {
    appName: "",
    instanceName: "",
    instanceLabel: "",
    // Role of the instance: a spoke has no accounts and no sessions
    mode: "",
    core: null,
  },
  mutations: {
    setInstanceName(state, instanceName) {
      state.instanceName = instanceName;
    },
    setInstanceLabel(state, instanceLabel) {
      state.instanceLabel = instanceLabel;
    },
    setCore(state, core) {
      state.core = core;
    },
    setAppName(state, appName) {
      state.appName = appName;
    },
    setMode(state, mode) {
      state.mode = mode;
    },
  },
  actions: {
    setInstanceNameInStore(context, instanceName) {
      context.commit("setInstanceName", instanceName);
    },
    setInstanceLabelInStore(context, instanceLabel) {
      context.commit("setInstanceLabel", instanceLabel);
    },
    setCoreInStore(context, core) {
      context.commit("setCore", core);
    },
    setAppNameInStore(context, appName) {
      context.commit("setAppName", appName);
    },
  },
  modules: {},
});
