<script setup>
import { ref, onMounted } from 'vue';
import FastnAPI from 'dashboard/api/integrations/fastn';
import Button from 'dashboard/components-next/button/Button.vue';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';

// The hub is fastn's page: it lists the integrations this account can turn on and lets an
// administrator connect the account's own Slack, Teams or CRM. Chatwoot only asks its backend
// for a short-lived address of that page, so the fastn API key never reaches the browser.
const loading = ref(true);
const iframeUrl = ref('');
const failed = ref(false);
const notConfigured = ref(false);

const loadSession = async () => {
  loading.value = true;
  failed.value = false;
  notConfigured.value = false;
  try {
    const { data } = await FastnAPI.createEmbedSession();
    iframeUrl.value = data.iframe_url;
  } catch (err) {
    notConfigured.value = err?.response?.data?.error === 'fastn_not_configured';
    failed.value = !notConfigured.value;
  } finally {
    loading.value = false;
  }
};

onMounted(loadSession);
</script>

<template>
  <SettingsLayout
    :is-loading="loading"
    :loading-message="$t('FASTN_INTEGRATION.LOADING')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="$t('FASTN_INTEGRATION.TITLE')"
        :description="$t('FASTN_INTEGRATION.DESCRIPTION')"
        :back-button-label="$t('INTEGRATION_SETTINGS.HEADER')"
      />
    </template>
    <template #body>
      <div class="flex flex-col gap-4 w-full">
        <p v-if="notConfigured" role="alert" class="text-n-ruby-11">
          {{ $t('FASTN_INTEGRATION.NOT_CONFIGURED') }}
        </p>
        <div v-else-if="failed" class="flex flex-col items-start gap-3">
          <p role="alert" class="text-n-ruby-11">
            {{ $t('FASTN_INTEGRATION.ERROR') }}
          </p>
          <Button :label="$t('FASTN_INTEGRATION.RETRY')" @click="loadSession" />
        </div>
        <iframe
          v-else-if="iframeUrl"
          :src="iframeUrl"
          :title="$t('FASTN_INTEGRATION.FRAME_TITLE')"
          class="w-full h-[720px] rounded-xl border border-n-weak bg-n-solid-1"
          allow="clipboard-write"
          referrerpolicy="strict-origin-when-cross-origin"
        />
      </div>
    </template>
  </SettingsLayout>
</template>
