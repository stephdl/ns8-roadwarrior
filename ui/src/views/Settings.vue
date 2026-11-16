<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <NsInlineNotification
              v-if="!configured && !loading.getConfiguration"
              kind="info"
              :title="$t('settings.first_configuration_title')"
              :description="$t('settings.first_configuration_description')"
              :showCloseButton="false"
              class="maxwidth"
            />
            <NsTextInput
              :label="$t('settings.host')"
              placeholder="vpn.example.org"
              v-model.trim="host"
              :helper-text="$t('settings.host_helper')"
              :invalid-message="$t(error.host)"
              :disabled="stillLoading"
              class="mg-bottom maxwidth"
              ref="host"
            />
            <NsTextInput
              type="number"
              min="1024"
              max="65535"
              v-model.number="port"
              :label="$t('settings.port')"
              :invalid-message="$t(error.port)"
              :disabled="stillLoading || hasAccounts"
              class="mg-bottom maxwidth"
              ref="port"
            >
              <template #tooltip>
                {{ $t("settings.port_tooltip") }}
              </template>
            </NsTextInput>
            <NsTextInput
              :label="$t('settings.network')"
              placeholder="10.8.0.0/24"
              v-model.trim="network"
              :helper-text="$t('settings.network_helper')"
              :invalid-message="$t(error.network)"
              :disabled="stillLoading || hasAccounts"
              class="mg-bottom maxwidth"
              ref="network"
            >
              <template #tooltip>
                {{ $t("settings.network_tooltip") }}
              </template>
            </NsTextInput>
            <label class="bx--label">{{ $t("settings.auth_mode") }}</label>
            <cv-radio-group vertical class="mg-bottom">
              <cv-radio-button
                v-model="authMode"
                value="certificate_password"
                :label="$t('settings.auth_certificate_password')"
                :disabled="stillLoading"
              />
              <cv-radio-button
                v-model="authMode"
                value="certificate"
                :label="$t('settings.auth_certificate')"
                :disabled="stillLoading"
              />
            </cv-radio-group>
            <template v-if="authMode === 'certificate_password'">
              <NsComboBox
                v-model="userDomain"
                :options="userDomainOptions"
                :autoFilter="true"
                :autoHighlight="true"
                :title="$t('settings.user_domain')"
                :label="$t('settings.choose_user_domain')"
                :invalid-message="$t(error.user_domain)"
                :disabled="stillLoading"
                class="mg-bottom maxwidth"
                ref="user_domain"
              />
              <NsInlineNotification
                v-if="!userDomainOptions.length && !loading.getConfiguration"
                kind="warning"
                :title="$t('settings.no_user_domain_title')"
                :description="$t('settings.no_user_domain_description')"
                :showCloseButton="false"
                class="maxwidth"
              />
              <NsToggle
                value="totpRequired"
                :label="$t('settings.totp_required')"
                v-model="totpRequired"
                :disabled="stillLoading"
                class="mg-bottom"
              >
                <template #tooltip>
                  {{ $t("settings.totp_required_tooltip") }}
                </template>
                <template slot="text-left">{{
                  $t("settings.disabled")
                }}</template>
                <template slot="text-right">{{
                  $t("settings.enabled")
                }}</template>
              </NsToggle>
            </template>
            <NsToggle
              value="exposeSamba"
              :label="$t('settings.expose_samba')"
              v-model="exposeSamba"
              :disabled="stillLoading || !sambaAvailable"
              class="mg-bottom"
            >
              <template #tooltip>
                {{ $t("settings.expose_samba_tooltip") }}
              </template>
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </NsToggle>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="stillLoading"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
    <cv-row v-if="configured">
      <cv-column>
        <cv-tile light>
          <h4 class="mg-bottom-sm">{{ $t("settings.restrict_apps_title") }}</h4>
          <p class="mg-bottom-sm maxwidth">
            {{ $t("settings.restrict_apps_description") }}
          </p>
          <NsCodeSnippet
            :copyTooltip="core.$t('common.copy_to_clipboard')"
            :copy-feedback="core.$t('common.copied_to_clipboard')"
            :feedback-aria-label="core.$t('common.copied_to_clipboard')"
            :wrap-text="true"
            :moreText="core.$t('common.show_more')"
            :lessText="core.$t('common.show_less')"
            hideExpandButton
            class="mg-bottom-sm maxwidth"
            >{{ ipAllowlist }}</NsCodeSnippet
          >
          <cv-link @click="goToHttpRoutes">
            {{ $t("settings.go_to_http_routes") }}
          </cv-link>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";
import ModuleTask from "@/mixins/moduleTask";

export default {
  name: "Settings",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
    ModuleTask,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      urlCheckInterval: null,
      configured: false,
      host: "",
      port: 1194,
      network: "10.8.0.0/24",
      authMode: "certificate_password",
      userDomain: "",
      userDomains: [],
      totpRequired: false,
      exposeSamba: false,
      sambaAvailable: false,
      ipAllowlist: "",
      hasAccounts: false,
      loading: {
        getConfiguration: false,
        configureModule: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        host: "",
        port: "",
        network: "",
        user_domain: "",
        totp_required: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    stillLoading() {
      return this.loading.getConfiguration || this.loading.configureModule;
    },
    userDomainOptions() {
      return this.userDomains.map((domain) => ({
        name: domain,
        label: domain,
        value: domain,
      }));
    },
  },
  created() {
    this.getConfiguration();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    goToHttpRoutes() {
      this.core.$router.push("/settings/http-routes");
    },
    getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      this.runModuleTask({
        action: "get-configuration",
        completed: this.getConfigurationCompleted,
        aborted: (message) => {
          this.error.getConfiguration = message;
          this.loading.getConfiguration = false;
        },
        failed: (message) => {
          this.error.getConfiguration = message;
          this.loading.getConfiguration = false;
        },
      });
    },
    getConfigurationCompleted(config) {
      this.configured = config.configured;
      this.host = config.host;
      this.port = config.port;
      this.network = config.network;
      this.authMode = config.auth_mode;
      this.userDomains = config.user_domains;
      // NsComboBox shows the label only if the option already exists when the value changes
      this.$nextTick(() => {
        this.userDomain = config.user_domain;
      });
      this.totpRequired = config.totp_required;
      this.sambaAvailable = config.samba_available;
      this.exposeSamba = config.expose_samba && config.samba_available;
      this.ipAllowlist = config.ip_allowlist;
      this.hasAccounts = config.has_accounts;
      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      let firstError = "";
      if (!this.host) {
        this.error.host = "common.required";
        firstError = firstError || "host";
      }
      if (
        !Number.isInteger(this.port) ||
        this.port < 1024 ||
        this.port > 65535
      ) {
        this.error.port = "settings.port_range";
        firstError = firstError || "port";
      }
      if (!/^\d{1,3}(\.\d{1,3}){3}\/\d{1,2}$/.test(this.network)) {
        this.error.network = "settings.invalid_network";
        firstError = firstError || "network";
      }
      if (this.authMode === "certificate_password" && !this.userDomain) {
        this.error.user_domain = "settings.user_domain_required";
        firstError = firstError || "user_domain";
      }
      if (firstError) {
        this.focusElement(firstError);
      }
      return !firstError;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      for (const validationError of validationErrors) {
        this.error[validationError.parameter] =
          "settings." + validationError.error;
      }
      this.focusElement(validationErrors[0].parameter);
    },
    configureModule() {
      if (!this.validateConfigureModule()) {
        return;
      }
      this.loading.configureModule = true;
      this.error.configureModule = "";
      const passwordMode = this.authMode === "certificate_password";
      this.runModuleTask({
        action: "configure-module",
        data: {
          host: this.host,
          port: this.port,
          network: this.network,
          auth_mode: this.authMode,
          user_domain: passwordMode ? this.userDomain : "",
          totp_required: passwordMode && this.totpRequired,
          expose_samba: this.exposeSamba,
        },
        title: this.$t("settings.configuring"),
        description: this.$t("settings.instance_configuration", {
          instance: this.instanceName,
        }),
        isNotificationHidden: false,
        completed: () => {
          this.loading.configureModule = false;
          this.getConfiguration();
        },
        validationFailed: this.configureModuleValidationFailed,
        aborted: (message) => {
          this.error.configureModule = message;
          this.loading.configureModule = false;
        },
        failed: (message) => {
          this.error.configureModule = message;
          this.loading.configureModule = false;
        },
      });
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.mg-bottom {
  margin-bottom: $spacing-06;
}

.mg-bottom-sm {
  margin-bottom: $spacing-04;
}

.maxwidth {
  max-width: 38rem;
}
</style>
