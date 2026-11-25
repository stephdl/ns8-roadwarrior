<!--
  Copyright (C) 2026 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <NsEmptyState :title="$t('spoke.title', { hub })">
    <template #description>
      <div class="mg-bottom">{{ $t("spoke.description") }}</div>
      <NsButton
        kind="ghost"
        :icon="ArrowRight20"
        :disabled="!hub"
        @click="goToAppPage(hub, page)"
        >{{ $t("spoke.go_to_hub") }}</NsButton
      >
    </template>
  </NsEmptyState>
</template>

<script>
import { IconService, UtilService } from "@nethserver/ns8-ui-lib";

export default {
  name: "SpokeEmptyState",
  mixins: [IconService, UtilService],
  props: {
    hub: { type: String, default: "" },
    // Page of the hub that holds what this spoke does not have
    page: { type: String, required: true },
  },
};
</script>
