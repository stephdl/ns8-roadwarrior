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
                <div v-if="vpnAddress" class="card-row">
                  {{ $t("status.vpn_address", { ip: vpnAddress }) }}
                </div>
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
            v-if="config.configured && config.mode !== 'spoke'"
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
                    @click="goToAppPage(instanceName, 'sessions')"
                    >{{ $t("status.go_to_sessions") }}</NsButton
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
    <cv-row v-if="config.mode === 'hub'">
      <cv-column>
        <cv-tile light class="mg-bottom">
          <h4 class="mg-bottom-sm">{{ $t("status.hub_nodes") }}</h4>
          <p class="mg-bottom-sm">{{ $t("status.hub_nodes_description") }}</p>
          <NsInlineNotification
            v-if="error.listSpokes"
            kind="error"
            :title="$t('action.list-spokes')"
            :description="error.listSpokes"
            :showCloseButton="false"
          />
          <cv-skeleton-text
            v-else-if="loading.listSpokes && !spokes.length"
            :paragraph="true"
            :line-count="3"
          />
          <cv-data-table
            v-else
            :columns="spokeColumns"
            :data="[]"
            :zebra="true"
          >
            <template slot="data">
              <cv-data-table-row v-for="spoke in spokes" :key="spoke.module_id">
                <cv-data-table-cell
                  >{{
                    spoke.node_name || $t("status.node") + " " + spoke.node_id
                  }}
                  ({{
                    spoke.leader ? $t("status.leader") : $t("status.worker")
                  }})</cv-data-table-cell
                >
                <cv-data-table-cell>{{ spoke.module_id }}</cv-data-table-cell>
                <cv-data-table-cell>{{ spoke.ip }}</cv-data-table-cell>
                <cv-data-table-cell>
                  <NsTag
                    :label="
                      spoke.connected
                        ? $t('status.connected')
                        : $t('status.disconnected')
                    "
                    :kind="spoke.connected ? 'green' : 'red'"
                  />
                </cv-data-table-cell>
                <cv-data-table-cell>
                  <NsButton
                    v-if="spoke.module_id !== instanceName"
                    kind="ghost"
                    size="small"
                    :icon="TrashCan20"
                    :loading="loading.removeSpoke === spoke.module_id"
                    @click="removeSpoke(spoke.module_id)"
                    >{{ $t("status.remove_node") }}</NsButton
                  >
                </cv-data-table-cell>
              </cv-data-table-row>
            </template>
          </cv-data-table>
        </cv-tile>
      </cv-column>
    </cv-row>
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

// Services that must run once configured, for each mode
const LONG_RUNNING_SERVICES = {
  standalone: ["openvpn-server", "openvpn-dns"],
  hub: [
    "openvpn-hub",
    "openvpn-hub-server",
    "openvpn-hub-dns",
    "openvpn-s2s",
    "openvpn-spoke",
  ],
  spoke: ["openvpn-spoke"],
};
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
      config: { configured: false, host: "", port: 0, mode: "standalone" },
      spokes: [],
      vpn: { running: false, sessions: [], ca_expiry: "" },
      status: { instance: "", services: [], images: [], volumes: [] },
      // Hide the server state until the first answer: a default "stopped" would mislead
      vpnLoaded: false,
      isShownRestartModuleModal: false,
      loading: {
        getStatus: false,
        getConfiguration: false,
        getVpnStatus: false,
        listSpokes: false,
        removeSpoke: "",
      },
      error: {
        getStatus: "",
        getConfiguration: "",
        getVpnStatus: "",
        listSpokes: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    vpnTitle() {
      if (!this.config.configured) {
        return this.$t("status.not_configured");
      }
      return this.config.mode === "spoke" ? this.config.hub : this.config.host;
    },
    vpnAddress() {
      // Address of this node for the VPN users: through its spoke on a hub, the server address otherwise
      if (!this.config.configured || this.config.mode === "spoke") {
        return "";
      }
      return this.config.mode === "hub"
        ? (this.config.spoke_ip || "").split("/")[0]
        : this.config.server_ip;
    },
    vpnDescription() {
      if (!this.config.configured) {
        return this.$t("status.vpn_server");
      }
      if (this.config.mode === "spoke") {
        return this.$t("status.spoke_of_hub", { ip: this.config.spoke_ip });
      }
      return this.$t(
        this.config.mode === "hub"
          ? "status.hub_server_port"
          : "status.vpn_server_port",
        { port: this.config.port }
      );
    },
    spokeColumns() {
      return [
        this.$t("status.node"),
        this.$t("status.instance"),
        this.$t("status.address"),
        this.$t("status.link"),
        "",
      ];
    },
    longRunningServices() {
      return LONG_RUNNING_SERVICES[this.config.mode] || [];
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
    failedServices() {
      // A stopped server is not "failed" for systemd, but it must run once configured
      return (this.status.services || []).filter(
        (service) =>
          service.failed ||
          (this.config.configured &&
            this.longRunningServices.includes(service.name) &&
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
          if (output.mode === "hub") {
            this.listSpokes();
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
    listSpokes() {
      this.loading.listSpokes = true;
      this.error.listSpokes = "";
      const fail = (message) => {
        this.error.listSpokes = message;
        this.loading.listSpokes = false;
      };
      this.runModuleTask({
        action: "list-spokes",
        completed: (output) => {
          this.spokes = output;
          this.loading.listSpokes = false;
        },
        aborted: fail,
        failed: fail,
      });
    },
    removeSpoke(moduleId) {
      this.loading.removeSpoke = moduleId;
      const done = () => {
        this.loading.removeSpoke = "";
        this.listSpokes();
      };
      this.runModuleTask({
        action: "remove-spoke",
        data: { module_id: moduleId },
        title: this.$t("status.removing_node", { module: moduleId }),
        isNotificationHidden: false,
        completed: done,
        aborted: (message) => {
          this.error.listSpokes = message;
          done();
        },
        failed: (message) => {
          this.error.listSpokes = message;
          done();
        },
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
