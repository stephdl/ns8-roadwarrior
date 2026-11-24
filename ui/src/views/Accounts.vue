<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("accounts.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div class="toolbar">
            <NsButton
              kind="primary"
              :icon="Add20"
              :disabled="loading.listAccounts || !configured"
              @click="showAddModal"
              >{{ $t("accounts.add_account") }}</NsButton
            >
            <NsButton
              kind="secondary"
              :icon="Restart20"
              :loading="loading.listAccounts"
              :disabled="loading.listAccounts || !configured"
              @click="listAccounts"
              >{{ $t("accounts.refresh") }}</NsButton
            >
            <NsButton
              kind="tertiary"
              :icon="Download20"
              :loading="loading.downloadAllHistory"
              :disabled="loading.downloadAllHistory || !configured"
              @click="downloadAllHistory"
              >{{ $t("accounts.download_all_history") }}</NsButton
            >
          </div>
          <NsDataTable
            :allRows="accounts"
            :columns="i18nTableColumns"
            :rawColumns="tableColumns"
            :sortable="true"
            :pageSizes="[10, 25, 50, 100]"
            :overflow-menu="true"
            isSearchable
            :filterRowsCallback="searchAccounts"
            :searchPlaceholder="$t('accounts.search')"
            :searchClearLabel="core.$t('common.clear_search')"
            :noSearchResultsLabel="core.$t('common.no_search_results')"
            :noSearchResultsDescription="
              core.$t('common.no_search_results_description')
            "
            :isLoading="loading.getConfiguration || loading.listAccounts"
            :skeletonRows="3"
            :isErrorShown="!!error.listAccounts"
            :errorTitle="$t('action.list-accounts')"
            :errorDescription="error.listAccounts"
            :itemsPerPageLabel="core.$t('pagination.items_per_page')"
            :rangeOfTotalItemsLabel="core.$t('pagination.range_of_total_items')"
            :ofTotalPagesLabel="core.$t('pagination.of_total_pages')"
            :backwardText="core.$t('pagination.previous_page')"
            :forwardText="core.$t('pagination.next_page')"
            :pageNumberLabel="core.$t('pagination.page_number')"
            @updatePage="tablePage = $event"
          >
            <template slot="empty-state">
              <NsEmptyState
                v-if="!configured"
                :title="$t('status.not_configured')"
              >
                <template #description>
                  <div class="mg-bottom">
                    {{ $t("accounts.not_configured_description") }}
                  </div>
                  <NsButton
                    kind="ghost"
                    :icon="ArrowRight20"
                    @click="goToAppPage(instanceName, 'settings')"
                    >{{ $t("status.configure") }}</NsButton
                  >
                </template>
              </NsEmptyState>
              <NsEmptyState v-else :title="$t('accounts.no_accounts')">
                <template #description>
                  <div class="mg-bottom">
                    {{ $t("accounts.no_accounts_description") }}
                  </div>
                  <NsButton
                    kind="primary"
                    :icon="Add20"
                    @click="showAddModal"
                    >{{ $t("accounts.add_account") }}</NsButton
                  >
                </template>
              </NsEmptyState>
            </template>
            <template slot="data">
              <cv-data-table-row
                v-for="(row, rowIndex) in tablePage"
                :key="`${rowIndex}`"
                :value="`${rowIndex}`"
              >
                <cv-data-table-cell class="break-word">{{
                  row.name
                }}</cv-data-table-cell>
                <cv-data-table-cell>
                  <NsTag
                    :label="$t('accounts.certificate_' + row.certificate)"
                    :kind="row.certificate === 'valid' ? 'green' : 'red'"
                  />
                </cv-data-table-cell>
                <cv-data-table-cell v-if="passwordMode">
                  <NsTag
                    :label="
                      row.totp_enrolled
                        ? $t('accounts.totp_enrolled')
                        : $t('accounts.totp_not_enrolled')
                    "
                    :kind="row.totp_enrolled ? 'green' : 'gray'"
                  />
                </cv-data-table-cell>
                <cv-data-table-cell>
                  <NsTag
                    v-if="row.disabled"
                    kind="high-contrast"
                    :label="$t('accounts.disabled')"
                  />
                  <NsTag
                    v-else
                    :label="
                      row.connected
                        ? $t('accounts.connected')
                        : $t('accounts.not_connected')
                    "
                    :kind="row.connected ? 'blue' : 'gray'"
                  />
                </cv-data-table-cell>
                <cv-data-table-cell>{{
                  formatTimestamp(row.last_login)
                }}</cv-data-table-cell>
                <cv-data-table-cell class="table-overflow-menu-cell">
                  <cv-overflow-menu flip-menu class="table-overflow-menu">
                    <cv-overflow-menu-item
                      :disabled="row.certificate !== 'valid'"
                      @click="downloadProfile(row)"
                    >
                      <NsMenuItem
                        :icon="Download20"
                        :label="$t('accounts.download_profile')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item
                      :disabled="row.certificate !== 'valid'"
                      @click="downloadProfile(row, 'zip')"
                    >
                      <NsMenuItem
                        :icon="Download20"
                        :label="$t('accounts.download_archive')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item @click="showHistoryModal(row)">
                      <NsMenuItem
                        :icon="RecentlyViewed20"
                        :label="$t('accounts.login_history')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item
                      v-if="passwordMode"
                      :disabled="row.disabled"
                      @click="startEnrollment(row)"
                    >
                      <NsMenuItem
                        :icon="Password20"
                        :label="
                          row.totp_enrolled
                            ? $t('accounts.replace_totp')
                            : $t('accounts.enroll_totp')
                        "
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item
                      v-if="passwordMode && row.totp_enrolled"
                      :disabled="row.disabled"
                      @click="showResetTotpModal(row)"
                    >
                      <NsMenuItem
                        :icon="Reset20"
                        :label="$t('accounts.reset_totp')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item
                      v-if="row.connected"
                      @click="killSession(row)"
                    >
                      <NsMenuItem
                        :icon="Logout20"
                        :label="$t('accounts.disconnect')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item
                      :disabled="row.disabled || row.certificate === 'revoked'"
                      @click="showRenewModal(row)"
                    >
                      <NsMenuItem
                        :icon="Renew20"
                        :label="$t('accounts.renew')"
                      />
                    </cv-overflow-menu-item>
                    <cv-overflow-menu-item @click="toggleAccount(row)">
                      <NsMenuItem
                        :icon="Power20"
                        :label="
                          row.disabled
                            ? $t('accounts.enable')
                            : $t('accounts.disable')
                        "
                      />
                    </cv-overflow-menu-item>
                    <NsMenuDivider />
                    <cv-overflow-menu-item danger @click="showRemoveModal(row)">
                      <NsMenuItem
                        :icon="TrashCan20"
                        :label="$t('accounts.remove')"
                      />
                    </cv-overflow-menu-item>
                  </cv-overflow-menu>
                </cv-data-table-cell>
              </cv-data-table-row>
            </template>
          </NsDataTable>
          <NsInlineNotification
            v-if="error.action"
            kind="error"
            :title="error.actionTitle"
            :description="error.action"
            :showCloseButton="true"
            @close="error.action = ''"
          />
        </cv-tile>
      </cv-column>
    </cv-row>
    <!-- add -->
    <NsModal
      size="default"
      :visible="isShownAddModal"
      :primary-button-disabled="loading.addAccount || !newName"
      :isLoading="loading.addAccount"
      @modal-hidden="isShownAddModal = false"
      @primary-click="addAccount"
    >
      <template slot="title">{{ $t("accounts.add_account") }}</template>
      <template slot="content">
        <cv-form @submit.prevent="addAccount" class="add-form">
          <p class="mg-bottom">
            {{
              passwordMode
                ? $t("accounts.add_description_password")
                : $t("accounts.add_description_certificate")
            }}
          </p>
          <NsComboBox
            v-if="passwordMode"
            v-model="newName"
            :options="userOptions"
            :autoFilter="true"
            :autoHighlight="true"
            :title="$t('accounts.user')"
            :label="$t('accounts.choose_user')"
            :invalid-message="$t(error.name)"
            :disabled="loading.listDomainUsers || loading.addAccount"
            ref="name"
          />
          <NsTextInput
            v-else
            v-model.trim="newName"
            :label="$t('accounts.name')"
            :helper-text="$t('accounts.name_helper')"
            :invalid-message="$t(error.name)"
            :disabled="loading.addAccount"
            ref="name"
          />
          <NsInlineNotification
            v-if="error.addAccount"
            kind="error"
            :title="$t('action.add-account')"
            :description="error.addAccount"
            :showCloseButton="false"
          />
        </cv-form>
      </template>
      <template slot="secondary-button">{{
        core.$t("common.cancel")
      }}</template>
      <template slot="primary-button">{{ $t("accounts.add") }}</template>
    </NsModal>
    <!-- TOTP enrollment: the secret is shown once -->
    <NsModal
      size="default"
      :visible="isShownTotpModal"
      :primary-button-disabled="
        !enrollment || loading.confirmTotp || !/^\d{6}$/.test(totpCode)
      "
      :isLoading="loading.confirmTotp"
      @modal-hidden="hideTotpModal"
      @primary-click="confirmTotp"
    >
      <template slot="title">{{
        $t("accounts.enroll_totp_title", { name: totpAccount })
      }}</template>
      <template slot="content">
        <cv-skeleton-text
          v-if="loading.enrollTotp"
          :paragraph="true"
          :line-count="5"
        />
        <NsInlineNotification
          v-if="error.enrollTotp"
          kind="error"
          :title="$t('action.enroll-totp')"
          :description="error.enrollTotp"
          :showCloseButton="false"
        />
        <template v-if="enrollment">
          <NsInlineNotification
            kind="warning"
            :title="$t('accounts.totp_once_title')"
            :description="$t('accounts.totp_once_description')"
            :showCloseButton="false"
          />
          <p class="mg-bottom">{{ $t("accounts.totp_scan") }}</p>
          <div class="qr mg-bottom">
            <img :src="qrDataUrl" :alt="$t('accounts.qr_alt')" />
          </div>
          <p class="mg-bottom-sm">{{ $t("accounts.totp_manual") }}</p>
          <NsCodeSnippet
            :copyTooltip="core.$t('common.copy_to_clipboard')"
            :copy-feedback="core.$t('common.copied_to_clipboard')"
            :feedback-aria-label="core.$t('common.copied_to_clipboard')"
            :wrap-text="true"
            hideExpandButton
            class="mg-bottom"
            >{{ enrollment.secret }}</NsCodeSnippet
          >
          <cv-form @submit.prevent="confirmTotp">
            <NsTextInput
              v-model.trim="totpCode"
              :label="$t('accounts.totp_code')"
              :helper-text="$t('accounts.totp_code_helper')"
              :invalid-message="$t(error.code)"
              :disabled="loading.confirmTotp"
              maxlength="6"
              ref="code"
            />
          </cv-form>
          <NsInlineNotification
            v-if="error.confirmTotp"
            kind="error"
            :title="$t('action.confirm-totp')"
            :description="error.confirmTotp"
            :showCloseButton="false"
          />
        </template>
      </template>
      <template slot="secondary-button">{{
        core.$t("common.cancel")
      }}</template>
      <template slot="primary-button">{{ $t("accounts.activate") }}</template>
    </NsModal>
    <!-- reset TOTP -->
    <NsModal
      size="default"
      kind="danger"
      :visible="isShownResetTotpModal"
      :isLoading="loading.resetTotp"
      :primary-button-disabled="loading.resetTotp"
      @modal-hidden="isShownResetTotpModal = false"
      @primary-click="resetTotp"
    >
      <template slot="title">{{ $t("accounts.reset_totp") }}</template>
      <template slot="content">
        <p>
          {{
            $t(
              totpRequired
                ? "accounts.reset_totp_description_required"
                : "accounts.reset_totp_description",
              { name: currentAccount }
            )
          }}
        </p>
      </template>
      <template slot="secondary-button">{{
        core.$t("common.cancel")
      }}</template>
      <template slot="primary-button">{{ $t("accounts.reset") }}</template>
    </NsModal>
    <!-- renew certificate -->
    <NsModal
      size="default"
      kind="danger"
      :visible="isShownRenewModal"
      :primary-button-disabled="loading.renewAccount"
      :isLoading="loading.renewAccount"
      @modal-hidden="isShownRenewModal = false"
      @primary-click="renewAccount"
    >
      <template slot="title">{{ $t("accounts.renew_title") }}</template>
      <template slot="content">
        <p>{{ $t("accounts.renew_description", { name: currentAccount }) }}</p>
      </template>
      <template slot="secondary-button">{{
        core.$t("common.cancel")
      }}</template>
      <template slot="primary-button">{{ $t("accounts.renew") }}</template>
    </NsModal>
    <!-- login history -->
    <NsModal
      size="large"
      :visible="isShownHistoryModal"
      :primary-button-disabled="
        loading.getLoginHistory || !filteredHistory.length
      "
      @modal-hidden="isShownHistoryModal = false"
      @primary-click="downloadHistory"
    >
      <template slot="title">{{
        $t("accounts.login_history_title", { name: currentAccount })
      }}</template>
      <template slot="content">
        <NsInlineNotification
          v-if="error.getLoginHistory"
          kind="error"
          :title="$t('action.get-login-history')"
          :description="error.getLoginHistory"
          :showCloseButton="false"
        />
        <div class="date-filter">
          <cv-date-picker
            kind="single"
            :cal-options="calOptions"
            :date-label="$t('accounts.history_from')"
            v-model="historyFrom"
            class="interval-date"
          />
          <cv-date-picker
            kind="single"
            :cal-options="calOptions"
            :date-label="$t('accounts.history_to')"
            v-model="historyTo"
            class="interval-date"
          />
        </div>
        <NsDataTable
          :allRows="filteredHistory"
          :columns="i18nHistoryColumns"
          :rawColumns="historyColumns"
          :sortable="false"
          :pageSizes="[10, 25, 50, 100]"
          :isSearchable="false"
          :isLoading="loading.getLoginHistory"
          :skeletonRows="5"
          :emptyStateTitle="$t('accounts.no_history')"
          :emptyStateDescription="$t('accounts.no_history_description')"
          :itemsPerPageLabel="core.$t('pagination.items_per_page')"
          :rangeOfTotalItemsLabel="core.$t('pagination.range_of_total_items')"
          :ofTotalPagesLabel="core.$t('pagination.of_total_pages')"
          :backwardText="core.$t('pagination.previous_page')"
          :forwardText="core.$t('pagination.next_page')"
          :pageNumberLabel="core.$t('pagination.page_number')"
          @updatePage="historyPage = $event"
        >
          <template slot="data">
            <cv-data-table-row
              v-for="(event, index) in historyPage"
              :key="index"
            >
              <cv-data-table-cell>{{
                formatTimestamp(event.time)
              }}</cv-data-table-cell>
              <cv-data-table-cell>
                <NsTag
                  :label="$t('accounts.event_' + event.event)"
                  :kind="eventKind(event.event)"
                />
              </cv-data-table-cell>
              <cv-data-table-cell>{{
                event.address || "-"
              }}</cv-data-table-cell>
              <cv-data-table-cell>{{ eventDetail(event) }}</cv-data-table-cell>
            </cv-data-table-row>
          </template>
        </NsDataTable>
      </template>
      <template slot="secondary-button">{{ core.$t("common.close") }}</template>
      <template slot="primary-button">{{
        $t("accounts.download_json")
      }}</template>
    </NsModal>
    <!-- remove -->
    <NsDangerDeleteModal
      :isShown="isShownRemoveModal"
      :name="currentAccount"
      :title="$t('accounts.remove_title')"
      :warning="core.$t('common.please_read_carefully')"
      :description="$t('accounts.remove_description', { name: currentAccount })"
      :typeToConfirm="
        core.$t('common.type_to_confirm', { name: currentAccount })
      "
      :isErrorShown="!!error.removeAccount"
      :errorTitle="$t('action.remove-account')"
      :errorDescription="error.removeAccount"
      @hide="isShownRemoveModal = false"
      @confirmDelete="removeAccount"
    />
  </cv-grid>
</template>

<script>
import QRCode from "qrcode";
import { mapState } from "vuex";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";
import ModuleTask from "@/mixins/moduleTask";
import { createSealKey, openSealed } from "@/lib/seal";
import Download20 from "@carbon/icons-vue/es/download/20";
import Password20 from "@carbon/icons-vue/es/password/20";
import Logout20 from "@carbon/icons-vue/es/logout/20";
import RecentlyViewed20 from "@carbon/icons-vue/es/recently-viewed/20";
import Power20 from "@carbon/icons-vue/es/power/20";
import Renew20 from "@carbon/icons-vue/es/renew/20";

export default {
  name: "Accounts",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
    ModuleTask,
  ],
  pageTitle() {
    return this.$t("accounts.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "accounts",
      },
      urlCheckInterval: null,
      Download20,
      Password20,
      Logout20,
      RecentlyViewed20,
      Power20,
      Renew20,
      isShownRenewModal: false,
      history: [],
      historyPage: [],
      historyColumns: ["time", "event", "address", "detail"],
      historyFrom: "",
      historyTo: "",
      calOptions: {
        dateFormat: "Y-m-d",
      },
      isShownHistoryModal: false,
      configured: false,
      authMode: "certificate_password",
      totpRequired: false,
      accounts: [],
      tablePage: [],
      domainUsers: [],
      newName: "",
      currentAccount: "",
      totpAccount: "",
      totpCode: "",
      enrollment: null,
      qrDataUrl: "",
      isShownAddModal: false,
      isShownTotpModal: false,
      isShownResetTotpModal: false,
      isShownRemoveModal: false,
      loading: {
        getConfiguration: false,
        listAccounts: false,
        listDomainUsers: false,
        addAccount: false,
        enrollTotp: false,
        confirmTotp: false,
        resetTotp: false,
        removeAccount: false,
        renewAccount: false,
        getLoginHistory: false,
        downloadAllHistory: false,
      },
      error: {
        listAccounts: "",
        addAccount: "",
        enrollTotp: "",
        confirmTotp: "",
        removeAccount: "",
        getLoginHistory: "",
        action: "",
        actionTitle: "",
        name: "",
        code: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    passwordMode() {
      return this.authMode === "certificate_password";
    },
    tableColumns() {
      const columns = ["name", "certificate"];
      if (this.passwordMode) {
        columns.push("totp");
      }
      return columns.concat(["session", "last_login"]);
    },
    filteredHistory() {
      // Local dates: the admin picks days of the browser time zone
      const from = this.historyFrom
        ? new Date(this.historyFrom + "T00:00:00").getTime() / 1000
        : -Infinity;
      const to = this.historyTo
        ? new Date(this.historyTo + "T23:59:59").getTime() / 1000
        : Infinity;
      return this.history.filter(
        (event) => event.time >= from && event.time <= to
      );
    },
    i18nHistoryColumns() {
      return this.historyColumns.map((column) =>
        this.$t("accounts.history_" + column)
      );
    },
    i18nTableColumns() {
      return this.tableColumns.map((column) =>
        this.$t("accounts.column_" + column)
      );
    },
    userOptions() {
      const taken = new Set(this.accounts.map((account) => account.name));
      return this.domainUsers
        .filter((user) => !taken.has(user.user))
        .map((user) => ({
          name: user.user,
          label: user.display_name
            ? `${user.user} (${user.display_name})`
            : user.user,
          value: user.user,
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
    getConfiguration() {
      this.loading.getConfiguration = true;
      this.runModuleTask({
        action: "get-configuration",
        completed: (config) => {
          this.$store.commit("setMode", config.mode);
          if (config.mode === "spoke") {
            // The users of a spoke connect to its hub
            this.goToAppPage(this.instanceName, "status");
            return;
          }
          this.configured = config.configured;
          this.authMode = config.auth_mode;
          this.totpRequired = config.totp_required;
          this.loading.getConfiguration = false;
          if (this.configured) {
            this.listAccounts();
          }
        },
        aborted: (message) => {
          this.error.listAccounts = message;
          this.loading.getConfiguration = false;
        },
        failed: (message) => {
          this.error.listAccounts = message;
          this.loading.getConfiguration = false;
        },
      });
    },
    listAccounts() {
      this.loading.listAccounts = true;
      this.error.listAccounts = "";
      this.runModuleTask({
        action: "list-accounts",
        completed: (accounts) => {
          this.accounts = accounts;
          this.loading.listAccounts = false;
        },
        aborted: (message) => {
          this.error.listAccounts = message;
          this.loading.listAccounts = false;
        },
        failed: (message) => {
          this.error.listAccounts = message;
          this.loading.listAccounts = false;
        },
      });
    },
    showAddModal() {
      this.newName = "";
      this.error.name = "";
      this.error.addAccount = "";
      this.isShownAddModal = true;
      if (this.passwordMode) {
        this.loading.listDomainUsers = true;
        this.runModuleTask({
          action: "list-domain-users",
          completed: (users) => {
            this.domainUsers = users;
            this.loading.listDomainUsers = false;
          },
          aborted: (message) => {
            this.error.addAccount = message;
            this.loading.listDomainUsers = false;
          },
          failed: (message) => {
            this.error.addAccount = message;
            this.loading.listDomainUsers = false;
          },
        });
      }
    },
    addAccount() {
      if (!this.newName) {
        return;
      }
      this.loading.addAccount = true;
      this.error.name = "";
      this.error.addAccount = "";
      this.runModuleTask({
        action: "add-account",
        data: { name: this.newName },
        completed: () => {
          this.loading.addAccount = false;
          this.isShownAddModal = false;
          this.listAccounts();
        },
        validationFailed: (errors) => {
          this.loading.addAccount = false;
          this.error.name = "accounts." + errors[0].error;
        },
        aborted: (message) => {
          this.error.addAccount = message;
          this.loading.addAccount = false;
        },
        failed: (message) => {
          this.error.addAccount = message;
          this.loading.addAccount = false;
        },
      });
    },
    formatTimestamp(seconds) {
      return seconds ? new Date(seconds * 1000).toLocaleString() : "-";
    },
    eventKind(event) {
      return (
        { login: "green", logout: "gray", refused: "red" }[event] || "gray"
      );
    },
    eventDetail(event) {
      if (event.event === "refused") {
        return this.$t("accounts.reason_" + event.reason);
      }
      if (event.event === "logout") {
        return this.$t("accounts.session_summary", {
          duration: this.$options.filters.secondsFormat(event.duration),
          received: this.$options.filters.byteFormat(event.bytes_received),
          sent: this.$options.filters.byteFormat(event.bytes_sent),
        });
      }
      return event.vpn_address || "-";
    },
    showHistoryModal(row) {
      this.currentAccount = row.name;
      this.history = [];
      this.historyFrom = "";
      this.historyTo = "";
      this.error.getLoginHistory = "";
      this.isShownHistoryModal = true;
      this.loading.getLoginHistory = true;
      this.runModuleTask({
        action: "get-login-history",
        data: { name: row.name },
        isNotificationHidden: true,
        completed: (result) => {
          this.history = result.events;
          this.loading.getLoginHistory = false;
        },
        aborted: (message) => {
          this.error.getLoginHistory = message;
          this.loading.getLoginHistory = false;
        },
        failed: (message) => {
          this.error.getLoginHistory = message;
          this.loading.getLoginHistory = false;
        },
      });
    },
    saveBlob(blob, filename) {
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = filename;
      link.click();
      URL.revokeObjectURL(link.href);
    },
    saveJson(data, filename) {
      this.saveBlob(
        new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }),
        filename
      );
    },
    historyFileDate() {
      // Local date and time: two downloads the same day get two names
      const now = new Date();
      const pad = (n) => String(n).padStart(2, "0");
      return (
        `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(
          now.getDate()
        )}` + `_${pad(now.getHours())}${pad(now.getMinutes())}`
      );
    },
    downloadHistory() {
      this.saveJson(
        this.filteredHistory,
        `${this.instanceName}-login-history-user-${
          this.currentAccount
        }-${this.historyFileDate()}.json`
      );
    },
    downloadAllHistory() {
      this.error.action = "";
      this.loading.downloadAllHistory = true;
      this.runModuleTask({
        action: "get-login-history",
        data: {},
        isNotificationHidden: true,
        completed: (result) => {
          this.loading.downloadAllHistory = false;
          this.saveJson(
            result.events,
            `${
              this.instanceName
            }-login-history-all-users-${this.historyFileDate()}.json`
          );
        },
        aborted: (message) => {
          this.loading.downloadAllHistory = false;
          this.actionFailed("get-login-history")(message);
        },
        failed: (message) => {
          this.loading.downloadAllHistory = false;
          this.actionFailed("get-login-history")(message);
        },
      });
    },
    actionFailed(action) {
      return (message) => {
        this.error.actionTitle = this.$t("action." + action);
        this.error.action = message;
      };
    },
    async downloadProfile(row, format = "ovpn") {
      this.error.action = "";
      const seal = await createSealKey();
      this.runModuleTask({
        action: "download-client-config",
        data: { name: row.name, format, public_key: seal.publicKey },
        // The profile holds the private key of the client
        isNotificationHidden: true,
        completed: async (sealed) => {
          const result = await openSealed(sealed, seal.privateKey);
          const blob = result.archive
            ? new Blob(
                [Uint8Array.from(atob(result.archive), (c) => c.charCodeAt(0))],
                { type: "application/zip" }
              )
            : new Blob([result.profile], {
                type: "application/x-openvpn-profile",
              });
          this.saveBlob(blob, result.filename);
        },
        validationFailed: (errors) => {
          this.actionFailed("download-client-config")(
            this.$t("accounts." + errors[0].error)
          );
        },
        aborted: this.actionFailed("download-client-config"),
        failed: this.actionFailed("download-client-config"),
      });
    },
    async startEnrollment(row) {
      this.totpAccount = row.name;
      this.totpCode = "";
      this.enrollment = null;
      this.qrDataUrl = "";
      this.error.enrollTotp = "";
      this.error.confirmTotp = "";
      this.error.code = "";
      this.isShownTotpModal = true;
      this.loading.enrollTotp = true;
      const seal = await createSealKey();
      this.runModuleTask({
        action: "enroll-totp",
        data: { name: row.name, public_key: seal.publicKey },
        isNotificationHidden: true,
        completed: async (sealed) => {
          const result = await openSealed(sealed, seal.privateKey);
          this.enrollment = result;
          this.qrDataUrl = await QRCode.toDataURL(result.uri, { margin: 1 });
          this.loading.enrollTotp = false;
          this.$nextTick(() => this.focusElement("code"));
        },
        validationFailed: (errors) => {
          this.error.enrollTotp = this.$t("accounts." + errors[0].error);
          this.loading.enrollTotp = false;
        },
        aborted: (message) => {
          this.error.enrollTotp = message;
          this.loading.enrollTotp = false;
        },
        failed: (message) => {
          this.error.enrollTotp = message;
          this.loading.enrollTotp = false;
        },
      });
    },
    hideTotpModal() {
      this.isShownTotpModal = false;
      // Forget the secret: it cannot be shown again
      this.enrollment = null;
      this.qrDataUrl = "";
      this.totpCode = "";
    },
    confirmTotp() {
      if (!/^\d{6}$/.test(this.totpCode)) {
        return;
      }
      this.loading.confirmTotp = true;
      this.error.code = "";
      this.error.confirmTotp = "";
      this.runModuleTask({
        action: "confirm-totp",
        data: { name: this.totpAccount, code: this.totpCode },
        completed: () => {
          this.loading.confirmTotp = false;
          this.hideTotpModal();
          this.listAccounts();
        },
        validationFailed: (errors) => {
          this.loading.confirmTotp = false;
          this.error.code = "accounts." + errors[0].error;
        },
        aborted: (message) => {
          this.error.confirmTotp = message;
          this.loading.confirmTotp = false;
        },
        failed: (message) => {
          this.error.confirmTotp = message;
          this.loading.confirmTotp = false;
        },
      });
    },
    showResetTotpModal(row) {
      this.currentAccount = row.name;
      this.isShownResetTotpModal = true;
    },
    resetTotp() {
      this.loading.resetTotp = true;
      this.runModuleTask({
        action: "reset-totp",
        data: { name: this.currentAccount },
        completed: () => {
          this.loading.resetTotp = false;
          this.isShownResetTotpModal = false;
          this.listAccounts();
        },
        validationFailed: (errors) => {
          this.loading.resetTotp = false;
          this.isShownResetTotpModal = false;
          this.actionFailed("reset-totp")(
            this.$t("accounts." + errors[0].error)
          );
          this.listAccounts();
        },
        aborted: (message) => {
          this.loading.resetTotp = false;
          this.isShownResetTotpModal = false;
          this.actionFailed("reset-totp")(message);
        },
        failed: (message) => {
          this.loading.resetTotp = false;
          this.isShownResetTotpModal = false;
          this.actionFailed("reset-totp")(message);
        },
      });
    },
    accountLabels(row) {
      // The words shown in the row, in the language of the page
      return [
        row.name,
        this.$t("accounts.certificate_" + row.certificate),
        this.$t(
          row.totp_enrolled
            ? "accounts.totp_enrolled"
            : "accounts.totp_not_enrolled"
        ),
        this.$t(
          row.disabled
            ? "accounts.disabled"
            : row.connected
            ? "accounts.connected"
            : "accounts.not_connected"
        ),
        this.$t(row.disabled ? "accounts.disabled" : "accounts.enabled"),
        this.formatTimestamp(row.last_login),
      ];
    },
    searchAccounts(query) {
      const text = query.trim().toLowerCase();
      if (!text) {
        return this.accounts;
      }
      return this.accounts.filter((row) =>
        this.accountLabels(row).some((label) =>
          label.toLowerCase().includes(text)
        )
      );
    },
    showRenewModal(row) {
      this.currentAccount = row.name;
      this.isShownRenewModal = true;
    },
    renewAccount() {
      this.loading.renewAccount = true;
      this.error.action = "";
      const done = () => {
        this.loading.renewAccount = false;
        this.isShownRenewModal = false;
        this.listAccounts();
      };
      this.runModuleTask({
        action: "renew-account",
        data: { name: this.currentAccount },
        isNotificationHidden: false,
        completed: done,
        validationFailed: (errors) => {
          done();
          this.actionFailed("renew-account")(
            this.$t("accounts." + errors[0].error)
          );
        },
        aborted: (message) => {
          done();
          this.actionFailed("renew-account")(message);
        },
        failed: (message) => {
          done();
          this.actionFailed("renew-account")(message);
        },
      });
    },
    toggleAccount(row) {
      const action = row.disabled ? "enable-account" : "disable-account";
      this.error.action = "";
      this.runModuleTask({
        action,
        data: { name: row.name },
        title: this.$t(
          row.disabled ? "accounts.enable_title" : "accounts.disable_title",
          { name: row.name }
        ),
        isNotificationHidden: false,
        completed: () => this.listAccounts(),
        validationFailed: (errors) => {
          this.actionFailed(action)(this.$t("accounts." + errors[0].error));
          this.listAccounts();
        },
        aborted: this.actionFailed(action),
        failed: this.actionFailed(action),
      });
    },
    killSession(row) {
      this.runModuleTask({
        action: "kill-session",
        data: { name: row.name },
        completed: () => this.listAccounts(),
        validationFailed: (errors) => {
          this.actionFailed("kill-session")(
            this.$t("accounts." + errors[0].error)
          );
          this.listAccounts();
        },
        aborted: this.actionFailed("kill-session"),
        failed: this.actionFailed("kill-session"),
      });
    },
    showRemoveModal(row) {
      this.currentAccount = row.name;
      this.error.removeAccount = "";
      this.isShownRemoveModal = true;
    },
    removeAccount() {
      this.loading.removeAccount = true;
      this.error.removeAccount = "";
      this.runModuleTask({
        action: "remove-account",
        data: { name: this.currentAccount },
        isNotificationHidden: false,
        completed: () => {
          this.loading.removeAccount = false;
          this.isShownRemoveModal = false;
          this.listAccounts();
        },
        validationFailed: (errors) => {
          this.error.removeAccount = this.$t("accounts." + errors[0].error);
          this.loading.removeAccount = false;
          this.listAccounts();
        },
        aborted: (message) => {
          this.error.removeAccount = message;
          this.loading.removeAccount = false;
        },
        failed: (message) => {
          this.error.removeAccount = message;
          this.loading.removeAccount = false;
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

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: $spacing-05;
  margin-bottom: $spacing-05;
}

.date-filter {
  display: flex;
  flex-wrap: wrap;
  gap: $spacing-05;
  margin-bottom: $spacing-05;
}

// The modal body scrolls: leave room so the user list opens without being cut
.add-form {
  min-height: 22rem;
}

.qr img {
  width: 12rem;
  height: 12rem;
  image-rendering: pixelated;
}
</style>
