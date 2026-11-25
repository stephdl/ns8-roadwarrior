<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("nodes.title") }}</h2>
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
    <cv-row v-if="error.removeSpoke">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.remove-spoke')"
          :description="error.removeSpoke"
          @close="error.removeSpoke = ''"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <p class="mg-bottom">{{ $t("nodes.description") }}</p>
          <div class="toolbar">
            <NsButton
              kind="secondary"
              :icon="Restart20"
              :loading="loading.listSpokes"
              :disabled="loading.listSpokes || !isHub"
              @click="listSpokes"
              >{{ $t("nodes.refresh") }}</NsButton
            >
          </div>
          <NsDataTable
            :allRows="spokes"
            :columns="i18nColumns"
            :rawColumns="columns"
            :sortable="true"
            :pageSizes="[10, 25, 50, 100]"
            :overflow-menu="true"
            isSearchable
            :filterRowsCallback="searchNodes"
            :searchPlaceholder="$t('nodes.search')"
            :searchClearLabel="core.$t('common.clear_search')"
            :noSearchResultsLabel="core.$t('common.no_search_results')"
            :noSearchResultsDescription="
              core.$t('common.no_search_results_description')
            "
            :isLoading="loading.getConfiguration || !loaded"
            :skeletonRows="3"
            :isErrorShown="!!error.listSpokes"
            :errorTitle="$t('action.list-spokes')"
            :errorDescription="error.listSpokes"
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
                v-if="!config.configured"
                :title="$t('status.not_configured')"
              >
                <template #description>
                  <div class="mg-bottom">
                    {{ $t("nodes.not_configured_description") }}
                  </div>
                  <NsButton
                    kind="ghost"
                    :icon="ArrowRight20"
                    @click="goToAppPage(instanceName, 'settings')"
                    >{{ $t("status.configure") }}</NsButton
                  >
                </template>
              </NsEmptyState>
              <NsEmptyState v-else :title="$t('nodes.no_nodes')">
                <template #description>
                  {{ $t("nodes.no_nodes_description") }}
                </template>
              </NsEmptyState>
            </template>
            <template slot="data">
              <cv-data-table-row
                v-for="row in tablePage"
                :key="row.module_id"
                :value="row.module_id"
              >
                <cv-data-table-cell class="break-word"
                  >{{ nodeLabel(row) }} ({{
                    row.leader ? $t("nodes.leader") : $t("nodes.worker")
                  }})</cv-data-table-cell
                >
                <cv-data-table-cell>{{ row.module_id }}</cv-data-table-cell>
                <cv-data-table-cell>{{ row.ip }}</cv-data-table-cell>
                <cv-data-table-cell>{{
                  row.expose_samba ? $t("nodes.open") : $t("nodes.closed")
                }}</cv-data-table-cell>
                <cv-data-table-cell>{{
                  row.expose_ssh ? $t("nodes.open") : $t("nodes.closed")
                }}</cv-data-table-cell>
                <cv-data-table-cell>
                  <NsTag
                    :label="
                      row.connected
                        ? $t('nodes.connected')
                        : $t('nodes.disconnected')
                    "
                    :kind="row.connected ? 'green' : 'red'"
                  />
                </cv-data-table-cell>
                <cv-data-table-cell class="table-overflow-menu-cell">
                  <!-- The spoke of the hub node goes away with the hub -->
                  <cv-overflow-menu
                    v-if="row.module_id !== instanceName"
                    flip-menu
                    class="table-overflow-menu"
                  >
                    <cv-overflow-menu-item
                      danger
                      :disabled="loading.removeSpoke === row.module_id"
                      @click="removeSpoke(row.module_id)"
                    >
                      <NsMenuItem
                        :icon="TrashCan20"
                        :label="$t('nodes.remove_node')"
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
import Restart20 from "@carbon/icons-vue/es/restart/20";

export default {
  name: "Nodes",
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
    ModuleTask,
  ],
  pageTitle() {
    return this.$t("nodes.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "nodes",
      },
      urlCheckInterval: null,
      Restart20,
      config: { configured: false, mode: "hub" },
      spokes: [],
      tablePage: [],
      loaded: false,
      columns: ["node", "instance", "address", "samba", "ssh", "link"],
      loading: {
        getConfiguration: false,
        listSpokes: false,
        removeSpoke: "",
      },
      error: {
        getConfiguration: "",
        listSpokes: "",
        removeSpoke: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
    isHub() {
      return this.config.configured && this.config.mode === "hub";
    },
    i18nColumns() {
      return this.columns.map((column) => this.$t("nodes.column_" + column));
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
    nodeLabel(row) {
      return row.node_name || this.$t("status.node") + " " + row.node_id;
    },
    searchNodes(query) {
      const text = query.trim().toLowerCase();
      if (!text) {
        return this.spokes;
      }
      return this.spokes.filter((row) =>
        [this.nodeLabel(row), String(row.node_id), row.module_id, row.ip].some(
          (value) => (value || "").toLowerCase().includes(text)
        )
      );
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
        completed: (config) => {
          this.config = config;
          this.$store.commit("setMode", config.mode);
          this.loading.getConfiguration = false;
          if (this.isHub) {
            this.listSpokes();
          } else {
            this.loaded = true;
          }
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
        this.loaded = true;
      };
      this.runModuleTask({
        action: "list-spokes",
        completed: (output) => {
          this.spokes = output;
          this.loaded = true;
          this.loading.listSpokes = false;
        },
        aborted: fail,
        failed: fail,
      });
    },
    removeSpoke(moduleId) {
      this.loading.removeSpoke = moduleId;
      this.error.removeSpoke = "";
      const done = () => {
        this.loading.removeSpoke = "";
        this.listSpokes();
      };
      const failed = (message) => {
        this.error.removeSpoke = message;
        done();
      };
      this.runModuleTask({
        action: "remove-spoke",
        data: { module_id: moduleId },
        title: this.$t("nodes.removing_node", { module: moduleId }),
        isNotificationHidden: false,
        completed: done,
        aborted: failed,
        failed,
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

.toolbar {
  display: flex;
  flex-wrap: wrap;
  gap: $spacing-05;
  margin-bottom: $spacing-05;
}
</style>
