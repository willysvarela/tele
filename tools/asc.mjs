#!/usr/bin/env node
// App Store Connect API client for Tele. Auth from the environment:
//   ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH (the .p8 file; never commit it)
// Usage: node tools/asc.mjs <command> [args]   (commands listed at the bottom)
import { createPrivateKey, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';

const { ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH } = process.env;
if (!ASC_ISSUER_ID || !ASC_KEY_ID || !ASC_KEY_PATH) { console.error('set ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_PATH'); process.exit(1); }
export const BUNDLE_ID = 'com.willysvarela.teleremote';
const BASE = 'https://api.appstoreconnect.apple.com';
const b64url = (b) => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

function token() {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'ES256', kid: ASC_KEY_ID, typ: 'JWT' }));
  const payload = b64url(JSON.stringify({ iss: ASC_ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }));
  const sig = sign('sha256', Buffer.from(`${header}.${payload}`), { key: createPrivateKey(readFileSync(ASC_KEY_PATH)), dsaEncoding: 'ieee-p1363' });
  return `${header}.${payload}.${b64url(sig)}`;
}

export async function api(method, path, body) {
  const res = await fetch(path.startsWith('http') ? path : BASE + path, {
    method, headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) {
    const assoc = json.errors?.flatMap(e => Object.entries(e.meta?.associatedErrors ?? {}).flatMap(([k, v]) => v.map(x => `${k}: ${x.title} ${x.detail ?? ''}`))) ?? [];
    throw new Error(`${method} ${path} -> ${res.status}: ${json.errors?.map(e => e.title + (e.detail ? ' ' + e.detail : '')).join(' | ')}${assoc.length ? '\n  - ' + assoc.join('\n  - ') : ''}`);
  }
  return json;
}

export async function app() {
  const r = await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE_ID}&include=appStoreVersions,appInfos`);
  if (!r.data.length) throw new Error('no app with bundle id ' + BUNDLE_ID);
  return r;
}

const commands = {
  async status() {
    const r = await app();
    const a = r.data[0];
    console.log('app', a.id, a.attributes.name, 'sku', a.attributes.sku, 'locale', a.attributes.primaryLocale, 'contentRights', a.attributes.contentRightsDeclaration);
    for (const inc of r.included ?? []) {
      if (inc.type === 'appStoreVersions') console.log('version', inc.id, inc.attributes.versionString, inc.attributes.appVersionState ?? inc.attributes.appStoreState, 'release', inc.attributes.releaseType, 'copyright', inc.attributes.copyright);
      if (inc.type === 'appInfos') console.log('appInfo', inc.id, inc.attributes.state ?? inc.attributes.appStoreState);
    }
    const builds = await api('GET', `/v1/builds?filter[app]=${a.id}&sort=-uploadedDate&limit=5`);
    for (const b of builds.data) console.log('build', b.id, 'number', b.attributes.version, b.attributes.processingState, 'expired', b.attributes.expired, 'nonExemptEncryption', b.attributes.usesNonExemptEncryption);
    const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
    if (ver) {
      const loc = await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`);
      for (const l of loc.data) console.log('versionLocalization', l.id, l.attributes.locale, 'description:', !!l.attributes.description, 'support', l.attributes.supportUrl);
      const b = await api('GET', `/v1/appStoreVersions/${ver.id}/build`).catch(() => ({ data: null }));
      console.log('attached build', b.data?.id ?? 'none');
    }
    const info = (r.included ?? []).find(i => i.type === 'appInfos');
    if (info) {
      const il = await api('GET', `/v1/appInfos/${info.id}/appInfoLocalizations`);
      for (const l of il.data) console.log('infoLocalization', l.id, l.attributes.locale, l.attributes.name, '|', l.attributes.subtitle, '|', l.attributes.privacyPolicyUrl);
      const cat = await api('GET', `/v1/appInfos/${info.id}?include=primaryCategory,ageRatingDeclaration`);
      for (const inc of cat.included ?? []) console.log(inc.type, inc.id, JSON.stringify(inc.attributes).slice(0, 400));
    }
  },
};

commands.inspect = async () => {
  const r = await app(); const a = r.data[0];
  const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const info = (r.included ?? []).find(i => i.type === 'appInfos');
  const show = async (label, path) => { try { const j = await api('GET', path); console.log('##', label); console.log(JSON.stringify(j.data, null, 0).slice(0, 1500)); } catch (e) { console.log('##', label, 'ERR', e.message.slice(0, 300)); } };
  await show('ageRating', `/v1/appInfos/${info.id}/ageRatingDeclaration`);
  await show('categories', `/v1/appCategories?filter[platforms]=IOS&limit=50`);
  await show('priceSchedule', `/v1/apps/${a.id}/appPriceSchedule?include=manualPrices,baseTerritory`);
  await show('pricePoints USA', `/v1/apps/${a.id}/appPricePoints?filter[territory]=USA&limit=3`);
  await show('availability', `/v1/apps/${a.id}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=3`);
  await show('dataUsagePublishState', `/v1/apps/${a.id}/dataUsagePublishState`);
  await show('dataUsages', `/v1/apps/${a.id}/dataUsages?limit=5`);
  const loc = await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`);
  await show('screenshotSets', `/v1/appStoreVersionLocalizations/${loc.data[0].id}/appScreenshotSets`);
  await show('reviewDetail', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`);
  await show('phasedRelease', `/v1/appStoreVersions/${ver.id}/appStoreVersionPhasedRelease`);
};

import { createHash } from 'node:crypto';
import { statSync, openSync, readSync, closeSync } from 'node:fs';
const listing = JSON.parse(readFileSync(new URL('./listing.json', import.meta.url)));
const step = async (label, fn) => { try { const r = await fn(); console.log('OK ', label, r ?? ''); } catch (e) { console.log('ERR', label, e.message.slice(0, 500)); } };

commands.publish = async () => {
  const r = await app(); const a = r.data[0];
  const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const info = (r.included ?? []).find(i => i.type === 'appInfos');
  const L = listing;

  await step('version string + copyright', () => api('PATCH', `/v1/appStoreVersions/${ver.id}`, { data: { type: 'appStoreVersions', id: ver.id,
    attributes: { versionString: L.versionString, copyright: L.copyright, releaseType: 'AFTER_APPROVAL' } } }));
  await step('content rights', () => api('PATCH', `/v1/apps/${a.id}`, { data: { type: 'apps', id: a.id, attributes: { contentRightsDeclaration: 'DOES_NOT_USE_THIRD_PARTY_CONTENT' } } }));
  await step('category', () => api('PATCH', `/v1/appInfos/${info.id}`, { data: { type: 'appInfos', id: info.id,
    relationships: { primaryCategory: { data: { type: 'appCategories', id: L.primaryCategory } } } } }));
  await step('age rating', () => api('PATCH', `/v1/ageRatingDeclarations/${info.id}`, { data: { type: 'ageRatingDeclarations', id: info.id, attributes: {
    alcoholTobaccoOrDrugUseOrReferences: 'NONE', contests: 'NONE', gambling: false, gamblingSimulated: 'NONE', gunsOrOtherWeapons: 'NONE',
    healthOrWellnessTopics: false, lootBox: false, medicalOrTreatmentInformation: 'NONE', messagingAndChat: false, parentalControls: false,
    profanityOrCrudeHumor: 'NONE', ageAssurance: false, sexualContentGraphicAndNudity: 'NONE', sexualContentOrNudity: 'NONE', socialMedia: false,
    socialMediaAgeRestricted: false, horrorOrFearThemes: 'NONE', matureOrSuggestiveThemes: 'NONE', unrestrictedWebAccess: false,
    userGeneratedContent: false, violenceCartoonOrFantasy: 'NONE', violenceRealisticProlongedGraphicOrSadistic: 'NONE', violenceRealistic: 'NONE',
    advertising: false, ageRatingOverride: 'NONE', koreaAgeRatingOverride: 'NONE' } } }));
  const il = (await api('GET', `/v1/appInfos/${info.id}/appInfoLocalizations`)).data[0];
  await step('name, subtitle, privacy url', () => api('PATCH', `/v1/appInfoLocalizations/${il.id}`, { data: { type: 'appInfoLocalizations', id: il.id,
    attributes: { subtitle: L.subtitle, privacyPolicyUrl: L.privacyPolicyUrl } } }));
  const vl = (await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data[0];
  await step('description, keywords, urls', () => api('PATCH', `/v1/appStoreVersionLocalizations/${vl.id}`, { data: { type: 'appStoreVersionLocalizations', id: vl.id,
    attributes: { description: L.description, keywords: L.keywords, supportUrl: L.supportUrl, marketingUrl: L.marketingUrl, promotionalText: L.promotionalText } } }));
  await step('review notes', async () => {
    const existing = await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`).catch(() => ({ data: null }));
    const attributes = { notes: L.reviewNotes, demoAccountRequired: false };
    if (existing.data) return api('PATCH', `/v1/appStoreReviewDetails/${existing.data.id}`, { data: { type: 'appStoreReviewDetails', id: existing.data.id, attributes } });
    return api('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } } });
  });
  await step('price: free', async () => {
    const points = await api('GET', `/v1/apps/${a.id}/appPricePoints?filter[territory]=USA&limit=200`);
    const free = points.data.find(p => Number(p.attributes.customerPrice) === 0);
    return api('POST', '/v1/appPriceSchedules', { data: { type: 'appPriceSchedules',
      relationships: { app: { data: { type: 'apps', id: a.id } }, baseTerritory: { data: { type: 'territories', id: 'USA' } },
        manualPrices: { data: [{ type: 'appPrices', id: '${price0}' }] } } },
      included: [{ type: 'appPrices', id: '${price0}', attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free.id } } } }] });
  });
  await step('availability: all territories', () => commands.availability(a.id));
  await step('screenshots', async () => {
    const sets = await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`);
    let set = sets.data.find(s => s.attributes.screenshotDisplayType === L.screenshotDisplayType);
    if (!set) set = (await api('POST', '/v1/appScreenshotSets', { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: L.screenshotDisplayType },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: vl.id } } } } })).data;
    const have = (await api('GET', `/v1/appScreenshotSets/${set.id}/appScreenshots`)).data.map(s => s.attributes.fileName);
    for (const file of L.screenshots) {
      const name = file.split('/').pop();
      if (have.includes(name)) { console.log('   already there', name); continue; }
      const size = statSync(file).size;
      const shot = (await api('POST', '/v1/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName: name, fileSize: size },
        relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } } } })).data;
      const fd = openSync(file, 'r');
      for (const op of shot.attributes.uploadOperations) {
        const buf = Buffer.alloc(op.length); readSync(fd, buf, 0, op.length, op.offset);
        const headers = Object.fromEntries(op.requestHeaders.map(h => [h.name, h.value]));
        const res = await fetch(op.url, { method: op.method, headers, body: buf });
        if (!res.ok) throw new Error(`upload chunk ${res.status}`);
      }
      closeSync(fd);
      const md5 = createHash('md5').update(readFileSync(file)).digest('hex');
      await api('PATCH', `/v1/appScreenshots/${shot.id}`, { data: { type: 'appScreenshots', id: shot.id, attributes: { uploaded: true, sourceFileChecksum: md5 } } });
      console.log('   uploaded', name);
    }
    return set.id;
  });
  await step('attach build', async () => {
    const builds = await api('GET', `/v1/builds?filter[app]=${a.id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1`);
    const b = builds.data[0]; if (!b) throw new Error('no valid build');
    await api('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
    return `build ${b.attributes.version}`;
  });
};

commands.availability = async (appId) => {
  if (!appId) appId = (await app()).data[0].id;
  const t = await api('GET', '/v1/territories?limit=200');
  const ids = t.data.map((x, i) => ({ tid: `\${t${i}}`, territory: x.id }));
  const r = await api('POST', '/v2/appAvailabilities', {
    data: { type: 'appAvailabilities', attributes: { availableInNewTerritories: true },
      relationships: { app: { data: { type: 'apps', id: appId } },
        territoryAvailabilities: { data: ids.map(x => ({ type: 'territoryAvailabilities', id: x.tid })) } } },
    included: ids.map(x => ({ type: 'territoryAvailabilities', id: x.tid, attributes: { available: true },
      relationships: { territory: { data: { type: 'territories', id: x.territory } } } })),
  });
  return `${ids.length} territories (${r.data.id})`;
};

commands.screenshotState = async () => {
  const r = await app(); const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const vl = (await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreVersionLocalizations`)).data[0];
  const sets = (await api('GET', `/v1/appStoreVersionLocalizations/${vl.id}/appScreenshotSets`)).data;
  for (const set of sets) {
    const shots = (await api('GET', `/v1/appScreenshotSets/${set.id}/appScreenshots`)).data;
    for (const s of shots) console.log(set.attributes.screenshotDisplayType, s.attributes.fileName, s.attributes.assetDeliveryState?.state, (s.attributes.assetDeliveryState?.errors ?? []).map(e => e.description).join('; '));
  }
};

commands.availabilityState = async () => {
  const a = (await app()).data[0];
  const r = await api('GET', `/v1/apps/${a.id}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=50`);
  console.log('availableInNewTerritories', r.data.attributes.availableInNewTerritories, 'available territories', (r.included ?? []).filter(t => t.attributes.available).length);
};

commands.reviewContact = async () => {
  const r = await app(); const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const d = (await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`)).data;
  const a = d.attributes;
  console.log('contact', a.contactFirstName, a.contactLastName, '| email set:', !!a.contactEmail, '| phone set:', !!a.contactPhone);
};

commands.prices = async (territory = 'USA') => {
  const a = (await app()).data[0];
  const r = await api('GET', `/v1/apps/${a.id}/appPricePoints?filter[territory]=${territory}&limit=12`);
  console.log(r.data.map(p => p.attributes.customerPrice).join('  '));
  const sched = await api('GET', `/v1/apps/${a.id}/appPriceSchedule/manualPrices?include=appPricePoint`).catch(() => null);
  if (sched) console.log('current price:', (sched.included ?? []).map(p => p.attributes.customerPrice).join(', ') || 'none');
};

commands.setPrice = async (customerPrice, territory = 'USA') => {
  const a = (await app()).data[0];
  let url = `/v1/apps/${a.id}/appPricePoints?filter[territory]=${territory}&limit=200`, point;
  while (url && !point) { const r = await api('GET', url); point = r.data.find(p => p.attributes.customerPrice === customerPrice); url = r.links?.next; }
  if (!point) throw new Error('no price point ' + customerPrice);
  await api('POST', '/v1/appPriceSchedules', { data: { type: 'appPriceSchedules',
    relationships: { app: { data: { type: 'apps', id: a.id } }, baseTerritory: { data: { type: 'territories', id: territory } },
      manualPrices: { data: [{ type: 'appPrices', id: '${p}' }] } } },
    included: [{ type: 'appPrices', id: '${p}', attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: 'appPricePoints', id: point.id } } } }] });
  console.log('price set to', customerPrice, territory, '(other territories follow Apple\'s equalisation)');
};

commands.attachBuild = async (number) => {
  const r = await app(); const a = r.data[0]; const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  for (let i = 0; i < 54; i++) {
    const builds = (await api('GET', `/v1/builds?filter[app]=${a.id}&sort=-uploadedDate&limit=5`)).data;
    const b = builds.find(x => !number || x.attributes.version === number);
    if (b && b.attributes.processingState === 'VALID') {
      await api('PATCH', `/v1/appStoreVersions/${ver.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
      console.log(`attached build ${b.attributes.version}`); return;
    }
    console.log(`build ${number ?? 'latest'}: ${b ? b.attributes.processingState : 'not listed yet'}, waiting…`);
    await new Promise(res => setTimeout(res, 10000));
  }
  throw new Error('build not valid after 9 minutes');
};

commands.uploads = async () => {
  const a = (await app()).data[0];
  const show = async (label, path) => { try { const j = await api('GET', path); console.log('##', label); for (const d of j.data ?? []) console.log(JSON.stringify({ id: d.id, ...d.attributes }).slice(0, 700)); if (!j.data?.length) console.log('(none)'); } catch (e) { console.log('##', label, 'ERR', e.message.slice(0, 300)); } };
  await show('buildUploads', `/v1/apps/${a.id}/buildUploads?limit=10`);
  await show('preReleaseVersions', `/v1/preReleaseVersions?filter[app]=${a.id}`);
  await show('builds (all)', `/v1/builds?filter[app]=${a.id}&limit=10&sort=-uploadedDate`);
};

commands.territory = async (code = 'BRA') => {
  const a = (await app()).data[0];
  const av = (await api('GET', `/v1/apps/${a.id}/appAvailabilityV2`)).data;
  let url = `/v2/appAvailabilities/${av.id}/territoryAvailabilities?limit=50&include=territory`, total = 0, hit;
  while (url) { const r = await api('GET', url); total += r.data.length; hit ??= r.data.find(t => t.relationships?.territory?.data?.id === code); url = r.links?.next; }
  console.log(code, hit ? `available=${hit.attributes.available} releaseDate=${hit.attributes.releaseDate ?? 'immediate'}` : 'not listed', '| territories listed:', total);
};

commands.contact = async (first, last, email, phone) => {
  const r = await app(); const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const d = (await api('GET', `/v1/appStoreVersions/${ver.id}/appStoreReviewDetail`)).data;
  await api('PATCH', `/v1/appStoreReviewDetails/${d.id}`, { data: { type: 'appStoreReviewDetails', id: d.id,
    attributes: { contactFirstName: first, contactLastName: last, contactEmail: email, contactPhone: phone } } });
  console.log('review contact set');
};

commands.submit = async () => {
  const r = await app(); const a = r.data[0]; const ver = (r.included ?? []).find(i => i.type === 'appStoreVersions');
  const open = (await api('GET', `/v1/apps/${a.id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&filter[platform]=IOS`)).data[0];
  const sub = open ?? (await api('POST', '/v1/reviewSubmissions', { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: a.id } } } } })).data;
  const items = (await api('GET', `/v1/reviewSubmissions/${sub.id}/items`)).data;
  if (!items.length) await api('POST', '/v1/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } }, appStoreVersion: { data: { type: 'appStoreVersions', id: ver.id } } } } });
  const done = await api('PATCH', `/v1/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } });
  console.log('submitted:', done.data.attributes.state);
};

const [cmd, ...args] = process.argv.slice(2);
if (!commands[cmd]) { console.error('commands:', Object.keys(commands).join(', ')); process.exit(1); }
commands[cmd](...args).catch(e => { console.error(e.message); process.exit(1); });
