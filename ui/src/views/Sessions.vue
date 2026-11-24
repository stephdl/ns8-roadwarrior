<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("sessions.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getVpnStatus">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-vpn-status')"
          :description="error.getVpnStatus"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row v-if="error.action">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="error.actionTitle"
          :description="error.action"
          @close="error.action = ''"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div class="toolbar">
            <NsButton
              kind="secondary"
              :icon="Restart20"
              :loading="loading.getVpnStatus"
              :disabled="loading.getVpnStatus"
              @click="getVpnStatus"
              >{{ $t("sessions.refresh") }}</NsButton
            >
          </div>
          <NsDataTable
            :allRows="sessions"
            :columns="i18nColumns"
            :rawColumns="columns"
            :sortable="true"
            :pageSizes="[10, 25, 50, 100]"
            :overflow-menu="true"
            isSearchable
            :searchPlaceholder="$t('sessions.search')"
            :searchClearLabel="core.$t('common.clear_search')"
            :noSearchResultsLabel="core.$t('common.no_search_results')"
            :noSearchResultsDescription="
              core.$t('common.no_search_results_description')
            "
            :isLoading="loading.getVpnStatus && !loaded"
            :skeletonRows="3"
            :itemsPerPageLabel="core.$t('pagination.items_per_page')"
            :rangeOfTotalItemsLabel="core.$t('pagination.range_of_total_items')"
            :ofTotalPagesLabel="core.$t('pagination.of_total_pages')"
            :backwardText="core.$t('pagination.previous_page')"
            :forwardText="core.$t('pagination.next_page')"
            :pageNumberLabel="core.$t('pagination.page_number')"
            @updatePage="tablePage = $event"
          >
            <template slot="empty-state">
              <NsEmptyState :title="$t('sessions.no_sessions')" />
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
                <cv-data-table-cell>{{ row.vpn_address }}</cv-data-table-cell>
                <cv-data-table-cell>{{ row.real_address }}</cv-data-table-cell>
                <cv-data-table-cell>{{
                  formatTimestamp(row.connected_since)
                }}</cv-data-table-cell>
                <cv-data-table-cell
                  >{{ byteFormat(row.bytes_received) }} /
                  {{ byteFormat(row.bytes_sent) }}</cv-data-table-cell
                >
                <cv-data-table-cell class="table-overflow-menu-cell">
                  <cv-overflow-menu flip-menu class="table-overflow-menu">
                    <cv-overflow-menu-item @click="killSession(row)">
                      <NsMenuItem
                        :icon="Logout20"
                        :label="$t('sessions.disconnect')"
                      />
                    </cv-overflow-menu-item>
                  </cv-overflow-menu>
                </cv-data-table-cell>
              </cv-data-table-row>
            </template>
          </NsDataTable>
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
import Logout20 from "@carbon/icons-vue/es/logout/20";

// The server writes its status every 30 seconds: no point in asking more often
const REFRESH_SECONDS = 30;

export default {
  name: "Sessions",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
    ModuleTask,
  ],
  pageTitle() {
    return this.$t("sessions.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "sessions",
      },
      urlCheckInterval: null,
      refreshInterval: null,
      Logout20,
      sessions: [],
      tablePage: [],
      loaded: false,
      columns: ["name", "vpn_address", "real_address", "since", "traffic"],
      loading: {
        getVpnStatus: false,
      },
      error: {
        getVpnStatus: "",
        action: "",
        actionTitle: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    i18nColumns() {
      return this.columns.map((column) => this.$t("sessions.column_" + column));
    },
  },
  created() {
    // Opened from a link, the page may come before any other loaded the role
    this.runModuleTask({
      action: "get-configuration",
      completed: (config) => {
        this.$store.commit("setMode", config.mode);
        if (config.mode === "spoke") {
          this.goToAppPage(this.instanceName, "status");
        }
      },
      aborted: () => {},
      failed: () => {},
    });
    this.getVpnStatus();
    this.refreshInterval = setInterval(
      this.getVpnStatus,
      REFRESH_SECONDS * 1000
    );
  },
  beforeDestroy() {
    clearInterval(this.refreshInterval);
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
    formatTimestamp(seconds) {
      return seconds ? new Date(seconds * 1000).toLocaleString() : "-";
    },
    byteFormat(value) {
      return this.$options.filters.byteFormat(value);
    },
    getVpnStatus() {
      if (this.loading.getVpnStatus) {
        return;
      }
      this.loading.getVpnStatus = true;
      this.error.getVpnStatus = "";
      const fail = (message) => {
        this.error.getVpnStatus = message;
        this.loading.getVpnStatus = false;
      };
      this.runModuleTask({
        action: "get-vpn-status",
        completed: (output) => {
          this.sessions = output.sessions;
          this.loaded = true;
          this.loading.getVpnStatus = false;
        },
        aborted: fail,
        failed: fail,
      });
    },
    killSession(row) {
      this.error.action = "";
      const failed = (message) => {
        this.error.actionTitle = this.$t("action.kill-session");
        this.error.action = message;
        this.getVpnStatus();
      };
      this.runModuleTask({
        action: "kill-session",
        data: { name: row.name },
        isNotificationHidden: false,
        completed: () => this.getVpnStatus(),
        validationFailed: (errors) =>
          failed(this.$t("accounts." + errors[0].error)),
        aborted: failed,
        failed,
      });
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: $spacing-05;
  margin-bottom: $spacing-05;
}
</style>
