<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("status.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getStatus">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-status')"
          :description="error.getStatus"
          :showCloseButton="false"
        />
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
    <cv-row v-if="isCaNearExpiry">
      <cv-column>
        <NsInlineNotification
          kind="warning"
          :title="$t('status.ca_expiry_title')"
          :description="$t('status.ca_expiry_description', { date: caExpiry })"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <div
          class="card-grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 3xl:grid-cols-4"
        >
          <NsInfoCard
            light
            :title="vpnTitle"
            :description="vpnDescription"
            :icon="Network_232"
            :loading="loading.getConfiguration || loading.getVpnStatus"
            :isErrorShown="!!error.getConfiguration"
            :errorTitle="$t('error.cannot_retrieve_configuration')"
            :errorDescription="error.getConfiguration"
            class="min-height-card"
          >
            <template slot="content">
              <div class="card-rows">
                <div v-if="config.configured" class="card-row">
                  <NsTag
                    v-if="vpnLoaded"
                    :label="
                      vpn.running ? $t('status.running') : $t('status.stopped')
                    "
                    :kind="vpn.running ? 'green' : 'red'"
                  />
                </div>
                <NsButton
                  v-else
                  kind="ghost"
                  :icon="ArrowRight20"
                  @click="goToAppPage(instanceName, 'settings')"
                  >{{ $t("status.configure") }}</NsButton
                >
              </div>
            </template>
          </NsInfoCard>
          <NsInfoCard
            v-if="config.configured"
            light
            :title="String(vpn.sessions.length)"
            :description="$tc('status.connected_clients', vpn.sessions.length)"
            :icon="UserMultiple32"
            :loading="loading.getVpnStatus"
            class="min-height-card"
          >
            <template slot="content">
              <div class="card-rows">
                <div class="card-row">
                  <NsButton
                    kind="ghost"
                    :icon="ArrowRight20"
                    @click="goToAppPage(instanceName, 'accounts')"
                    >{{ $t("status.go_to_accounts") }}</NsButton
                  >
                </div>
              </div>
            </template>
          </NsInfoCard>
          <NsInfoCard
            light
            :title="status.instance || '-'"
            :description="$t('status.app_instance')"
            :icon="Application32"
            :loading="loading.getStatus"
            class="min-height-card"
          >
            <template slot="content">
              <div class="card-rows">
                <div class="card-row">
                  <NsButton
                    kind="ghost"
                    :icon="Restart20"
                    :disabled="loading.getStatus || !status.node"
                    @click="isShownRestartModuleModal = true"
                  >
                    {{ core.$t("apps_status.restart_application") }}
                  </NsButton>
                </div>
              </div>
            </template>
          </NsInfoCard>
          <NsInfoCard
            light
            :title="installationNodeTitle"
            :titleTooltip="installationNodeTitleTooltip"
            :description="$t('status.installation_node')"
            :icon="Chip32"
            :loading="loading.getStatus"
            class="min-height-card"
          >
            <template slot="content">
              <div class="card-rows">
                <div class="card-row">
                  <NsButton
                    kind="ghost"
                    :icon="ArrowRight20"
                    :disabled="loading.getStatus || !status.node"
                    @click="goToNodeDetails"
                  >
                    {{ core.$t("apps_status.go_to_node_details") }}
                  </NsButton>
                </div>
              </div>
            </template>
          </NsInfoCard>
        </div>
      </cv-column>
    </cv-row>
    <!-- sessions -->
    <template v-if="config.configured">
      <cv-row>
        <cv-column class="page-subtitle">
          <h4>{{ $t("status.sessions") }}</h4>
        </cv-column>
      </cv-row>
      <cv-row>
        <cv-column>
          <cv-tile light>
            <NsDataTable
              :allRows="vpn.sessions"
              :columns="i18nSessionColumns"
              :rawColumns="sessionColumns"
              :sortable="true"
              :pageSizes="[10, 25, 50, 100]"
              :overflow-menu="false"
              isSearchable
              :searchPlaceholder="$t('status.search_sessions')"
              :searchClearLabel="core.$t('common.clear_search')"
              :noSearchResultsLabel="core.$t('common.no_search_results')"
              :noSearchResultsDescription="
                core.$t('common.no_search_results_description')
              "
              :isLoading="loading.getVpnStatus"
              :skeletonRows="3"
              :itemsPerPageLabel="core.$t('pagination.items_per_page')"
              :rangeOfTotalItemsLabel="
                core.$t('pagination.range_of_total_items')
              "
              :ofTotalPagesLabel="core.$t('pagination.of_total_pages')"
              :backwardText="core.$t('pagination.previous_page')"
              :forwardText="core.$t('pagination.next_page')"
              :pageNumberLabel="core.$t('pagination.page_number')"
              @updatePage="sessionsPage = $event"
            >
              <template slot="empty-state">
                <NsEmptyState :title="$t('status.no_sessions')" />
              </template>
              <template slot="data">
                <cv-data-table-row
                  v-for="(row, rowIndex) in sessionsPage"
                  :key="`${rowIndex}`"
                  :value="`${rowIndex}`"
                >
                  <cv-data-table-cell class="break-word">{{
                    row.name
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{ row.vpn_address }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    row.real_address
                  }}</cv-data-table-cell>
                  <cv-data-table-cell>{{
                    formatTimestamp(row.connected_since)
                  }}</cv-data-table-cell>
                  <cv-data-table-cell
                    >{{ byteFormat(row.bytes_received) }} /
                    {{ byteFormat(row.bytes_sent) }}</cv-data-table-cell
                  >
                </cv-data-table-row>
              </template>
            </NsDataTable>
          </cv-tile>
        </cv-column>
      </cv-row>
    </template>
    <!-- services -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $t("status.failed_services") }}</h4>
      </cv-column>
    </cv-row>
    <cv-row v-if="!loading.getStatus">
      <cv-column v-if="!status.services.length">
        <cv-tile light>
          <NsEmptyState :title="$t('status.no_services')" />
        </cv-tile>
      </cv-column>
      <cv-column v-else-if="!failedServices.length">
        <cv-tile light>
          <NsEmptyState :title="$t('status.all_services_running')">
            <template #pictogram>
              <CircleCheckPictogram />
            </template>
          </NsEmptyState>
        </cv-tile>
      </cv-column>
      <cv-column v-else>
        <div
          class="card-grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 3xl:grid-cols-4"
        >
          <NsSystemdServiceCard
            v-for="service in failedServices"
            :key="service.name"
            light
            class="min-height-card"
            :serviceName="service.name"
            :active="service.active"
            :failed="service.failed"
            :enabled="service.enabled"
            :icon="Cube32"
          />
        </div>
      </cv-column>
    </cv-row>
    <cv-row v-else>
      <cv-column :md="4" :max="4">
        <cv-tile light>
          <cv-skeleton-text :paragraph="true" :line-count="4" />
        </cv-tile>
      </cv-column>
    </cv-row>
    <!-- images -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $tc("status.app_images", 2) }}</h4>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div v-if="!loading.getStatus">
            <NsEmptyState
              v-if="!status.images.length"
              :title="$t('status.no_images')"
            />
            <cv-structured-list v-else>
              <template slot="headings">
                <cv-structured-list-heading>{{
                  $t("status.name")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("status.size")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("status.created")
                }}</cv-structured-list-heading>
              </template>
              <template slot="items">
                <cv-structured-list-item
                  v-for="image in status.images"
                  :key="image.name"
                >
                  <cv-structured-list-data class="break-word">{{
                    image.name
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    image.size
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    image.created
                  }}</cv-structured-list-data>
                </cv-structured-list-item>
              </template>
            </cv-structured-list>
          </div>
          <cv-skeleton-text v-else :paragraph="true" :line-count="5" />
        </cv-tile>
      </cv-column>
    </cv-row>
    <!-- volumes -->
    <cv-row>
      <cv-column class="page-subtitle">
        <h4>{{ $tc("status.app_volumes", 2) }}</h4>
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <div v-if="!loading.getStatus">
            <NsEmptyState
              v-if="!status.volumes.length"
              :title="$t('status.no_volumes')"
            />
            <cv-structured-list v-else>
              <template slot="headings">
                <cv-structured-list-heading>{{
                  $t("status.name")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("status.mount")
                }}</cv-structured-list-heading>
                <cv-structured-list-heading>{{
                  $t("status.created")
                }}</cv-structured-list-heading>
              </template>
              <template slot="items">
                <cv-structured-list-item
                  v-for="volume in status.volumes"
                  :key="volume.name"
                >
                  <cv-structured-list-data class="break-word">{{
                    volume.name
                  }}</cv-structured-list-data>
                  <cv-structured-list-data class="break-word">{{
                    volume.mount
                  }}</cv-structured-list-data>
                  <cv-structured-list-data>{{
                    volume.created
                  }}</cv-structured-list-data>
                </cv-structured-list-item>
              </template>
            </cv-structured-list>
          </div>
          <cv-skeleton-text v-else :paragraph="true" :line-count="5" />
        </cv-tile>
      </cv-column>
    </cv-row>
    <RestartModuleModal
      :visible="isShownRestartModuleModal"
      :node="status.node"
      @hide="isShownRestartModuleModal = false"
    />
  </cv-grid>
</template>

<script>
import moduleTask from "@/mixins/moduleTask";
import { mapState } from "vuex";
import RestartModuleModal from "@/components/RestartModuleModal.vue";
import Restart20 from "@carbon/icons-vue/es/restart/20";
import Network_232 from "@carbon/icons-vue/es/network--2/32";
import UserMultiple32 from "@carbon/icons-vue/es/user--multiple/32";
import {
  QueryParamService,
  TaskService,
  IconService,
  UtilService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

const LONG_RUNNING_SERVICES = ["openvpn-server", "openvpn-dns"];
const CA_WARNING_DAYS = 90;

export default {
  name: "Status",
  components: { RestartModuleModal },
  mixins: [
    moduleTask,
    TaskService,
    QueryParamService,
    IconService,
    UtilService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("status.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "status",
      },
      urlCheckInterval: null,
      Restart20,
      Network_232,
      UserMultiple32,
      config: { configured: false, host: "", port: 0 },
      vpn: { running: false, sessions: [], ca_expiry: "" },
      status: { instance: "", services: [], images: [], volumes: [] },
      sessionsPage: [],
      // Hide the server state until the first answer: a default "stopped" would mislead
      vpnLoaded: false,
      sessionColumns: [
        "name",
        "vpn_address",
        "real_address",
        "since",
        "traffic",
      ],
      isShownRestartModuleModal: false,
      loading: {
        getStatus: false,
        getConfiguration: false,
        getVpnStatus: false,
      },
      error: {
        getStatus: "",
        getConfiguration: "",
        getVpnStatus: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    vpnTitle() {
      return this.config.configured
        ? this.config.host
        : this.$t("status.not_configured");
    },
    vpnDescription() {
      return this.config.configured
        ? this.$t("status.vpn_server_port", { port: this.config.port })
        : this.$t("status.vpn_server");
    },
    caExpiry() {
      const date = new Date(this.vpn.ca_expiry);
      return isNaN(date.getTime()) ? "" : date.toLocaleDateString();
    },
    isCaNearExpiry() {
      const date = new Date(this.vpn.ca_expiry);
      if (isNaN(date.getTime())) {
        return false;
      }
      return date - Date.now() < CA_WARNING_DAYS * 24 * 3600 * 1000;
    },
    i18nSessionColumns() {
      return this.sessionColumns.map((column) =>
        this.$t("status.column_" + column)
      );
    },
    failedServices() {
      // A stopped server is not "failed" for systemd, but it must run once configured
      return (this.status.services || []).filter(
        (service) =>
          service.failed ||
          (this.config.configured &&
            LONG_RUNNING_SERVICES.includes(service.name) &&
            !service.active)
      );
    },
    installationNodeTitle() {
      if (this.status && this.status.node) {
        return this.status.node_ui_name
          ? this.status.node_ui_name
          : this.$t("status.node") + " " + this.status.node;
      }
      return "-";
    },
    installationNodeTitleTooltip() {
      return this.status && this.status.node_ui_name
        ? this.$t("status.node") + " " + this.status.node
        : "";
    },
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
  created() {
    this.getStatus();
    this.getConfiguration();
  },
  methods: {
    byteFormat(value) {
      return this.$options.filters.byteFormat(value);
    },
    formatTimestamp(seconds) {
      return seconds ? new Date(seconds * 1000).toLocaleString() : "-";
    },
    goToNodeDetails() {
      if (this.status && this.status.node) {
        this.core.$router.push(`/nodes/${this.status.node}`);
      }
    },
    getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const fail = (message) => {
        this.error.getConfiguration = message;
        this.loading.getConfiguration = false;
      };
      this.runModuleTask({
        action: "get-configuration",
        completed: (output) => {
          this.config = output;
          this.loading.getConfiguration = false;
          if (output.configured) {
            this.getVpnStatus();
          }
        },
        aborted: fail,
        failed: fail,
      });
    },
    getVpnStatus() {
      this.loading.getVpnStatus = true;
      this.error.getVpnStatus = "";
      const fail = (message) => {
        this.error.getVpnStatus = message;
        this.loading.getVpnStatus = false;
      };
      this.runModuleTask({
        action: "get-vpn-status",
        completed: (output) => {
          this.vpn = output;
          this.vpnLoaded = true;
          this.loading.getVpnStatus = false;
        },
        aborted: fail,
        failed: fail,
      });
    },
    getStatus() {
      this.loading.getStatus = true;
      this.error.getStatus = "";
      const fail = (message) => {
        this.error.getStatus = message;
        this.loading.getStatus = false;
      };
      this.runModuleTask({
        action: "get-status",
        completed: (output) => {
          this.status = output;
          this.loading.getStatus = false;
        },
        aborted: fail,
        failed: fail,
      });
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";

.break-word {
  word-break: break-word;
}
</style>
