// -*- mode:C++; tab-width:8; c-basic-offset:2; indent-tabs-mode:t -*-
// vim: ts=2 sw=2 expandtab ft=cpp

/*
 * Ceph - scalable distributed file system
 *
 * SAL implementation for the CORTX DAOS backend
 *
 * Copyright (C) 2021 Seagate Technology LLC and/or its Affiliates
 *
 * This is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License version 2.1, as published by the Free Software
 * Foundation. See file COPYING.
 *
 */

#include "rgw_sal_daos.h"

#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

#include <sstream>
#include <system_error>

#include "common/Clock.h"
#include "common/errno.h"
#include "rgw_bucket.h"
#include "rgw_compression.h"
#include "rgw_sal.h"

#define dout_subsys ceph_subsys_rgw

using std::list;
using std::map;
using std::set;
using std::string;
using std::vector;

static string mp_ns = RGW_OBJ_NS_MULTIPART;

namespace rgw::sal {

using ::ceph::decode;
using ::ceph::encode;

int DaosUser::list_buckets(const DoutPrefixProvider* dpp, const string& marker,
                           const string& end_marker, uint64_t max,
                           bool need_stats, BucketList& buckets,
                           optional_yield y) {
  ldpp_dout(dpp, 20) << "DEBUG: list_user_buckets: marker=" << marker
                    << " end_marker=" << end_marker
                    << " max=" << max << dendl;
  int ret = 0;
  bool is_truncated = false;
  buckets.clear();
  daos_size_t bcount = max;
  vector<struct daos_pool_cont_info> daos_buckets(max);
  
  // XXX: Somehow handle markers and other bucket info
  ret = daos_pool_list_cont(store->poh, &bcount, daos_buckets.data(), nullptr);
  if (ret == -DER_TRUNC) {
    is_truncated = true;
  } else if (ret < 0) {
    ldpp_dout(dpp, 0) << "ERROR: daos_pool_list_cont failed!" << ret << dendl;
    return ret;
  }

  for (const auto& db: daos_buckets) {
    RGWBucketEnt ent = {};
    ent.bucket.name = db.pci_label;
    buckets.add(std::make_unique<DaosBucket>(this->store, ent, this));
  }

  buckets.set_truncated(is_truncated);
  return 0;
}

int DaosUser::create_bucket(
    const DoutPrefixProvider* dpp, const rgw_bucket& b,
    const std::string& zonegroup_id, rgw_placement_rule& placement_rule,
    std::string& swift_ver_location, const RGWQuotaInfo* pquota_info,
    const RGWAccessControlPolicy& policy, Attrs& attrs, RGWBucketInfo& info,
    obj_version& ep_objv, bool exclusive, bool obj_lock_enabled, bool* existed,
    req_info& req_info, std::unique_ptr<Bucket>* bucket_out, optional_yield y) {
  int ret;
  std::unique_ptr<Bucket> bucket;

  // Look up the bucket. Create it if it doesn't exist.
  ret = this->store->get_bucket(dpp, this, b, &bucket, y);
  if (ret < 0 && ret != -ENOENT) return ret;

  if (ret != -ENOENT) {
    *existed = true;
    if (swift_ver_location.empty()) {
      swift_ver_location = bucket->get_info().swift_ver_location;
    }
    placement_rule.inherit_from(bucket->get_info().placement_rule);

  } else {
    *existed = false;
    placement_rule.name = "default";
    placement_rule.storage_class = "STANDARD";
    DaosBucket* daos_bucket = new DaosBucket(store, b, this);
    bucket = std::unique_ptr<Bucket>(daos_bucket);
    bucket->set_attrs(attrs);

    ret = dfs_cont_create_with_label(store->poh, bucket->get_name().c_str(), NULL, &daos_bucket->cont_uuid, &daos_bucket->coh, &daos_bucket->dfs);
    if (ret < 0) {
      ldpp_dout(dpp, 0) << "ERROR: dfs_cont_create_with_label failed!" << ret << dendl;
    }
    daos_bucket->put_info(dpp, y, ceph::real_time())
  }

  bucket->set_version(ep_objv);
  bucket->get_info() = info;

  bucket_out->swap(bucket);

  return ret;
}

int DaosUser::read_attrs(const DoutPrefixProvider* dpp, optional_yield y) {
  return 0;
}

int DaosUser::read_stats(const DoutPrefixProvider* dpp, optional_yield y,
                         RGWStorageStats* stats,
                         ceph::real_time* last_stats_sync,
                         ceph::real_time* last_stats_update) {
  return 0;
}

/* stats - Not for first pass */
int DaosUser::read_stats_async(const DoutPrefixProvider* dpp,
                               RGWGetUserStats_CB* cb) {
  return 0;
}

int DaosUser::complete_flush_stats(const DoutPrefixProvider* dpp,
                                   optional_yield y) {
  return 0;
}

int DaosUser::read_usage(const DoutPrefixProvider* dpp, uint64_t start_epoch,
                         uint64_t end_epoch, uint32_t max_entries,
                         bool* is_truncated, RGWUsageIter& usage_iter,
                         map<rgw_user_bucket, rgw_usage_log_entry>& usage) {
  return 0;
}

int DaosUser::trim_usage(const DoutPrefixProvider* dpp, uint64_t start_epoch,
                         uint64_t end_epoch) {
  return 0;
}

int DaosUser::load_user(const DoutPrefixProvider* dpp, optional_yield y) {
  ldpp_dout(dpp, 20) << "load user: user id =   " << info.user_id.to_str()
                     << dendl;
  // XXX: implement actual code here
  rgw_user testid_user("tenant", "tester", "ns");
  info.user_id = testid_user;
  info.display_name = "Daos Explorer";
  info.user_email = "tester@seagate.com";
  RGWAccessKey k1("0555b35654ad1656d804", "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==");
  info.access_keys["0555b35654ad1656d804"] = k1;
  return 0;
}

int DaosUser::store_user(const DoutPrefixProvider* dpp, optional_yield y,
                         bool exclusive, RGWUserInfo* old_info) {
  ldpp_dout(dpp, 10) << "Store_user(): User = " << info.user_id.id << dendl;
  if (old_info)
      *old_info = info;
  return 0;
}

int DaosUser::remove_user(const DoutPrefixProvider* dpp, optional_yield y) {
  return 0;
}

int DaosBucket::refresh_handle() {
  int ret = 0;
  if (!daos_handle_is_valid(coh)) {
    daos_cont_info_t cont_info;
    ret = daos_cont_open(store->poh, info.bucket.name.c_str(), DAOS_COO_RW, &coh, &cont_info, nullptr);
    if (ret == 0) {
      uuid_copy(cont_uuid, cont_info.ci_uuid);
    }
  }
  return ret;
}

int DaosBucket::remove_bucket(const DoutPrefixProvider* dpp,
                              bool delete_children, bool forward_to_master,
                              req_info* req_info, optional_yield y) {
  int ret;

  ret = load_bucket(dpp, y);

  return ret;
}

int DaosBucket::remove_bucket_bypass_gc(int concurrent_max,
                                        bool keep_index_consistent,
                                        optional_yield y,
                                        const DoutPrefixProvider* dpp) {
  return 0;
}

int DaosBucket::put_info(const DoutPrefixProvider* dpp, bool exclusive,
                         ceph::real_time _mtime) {
  ldpp_dout(dpp, 20) << "put_info(): bucket_id=" << info.bucket.bucket_id
                     << dendl;
  
  int ret = refresh_handle();
  if (ret < 0) {
    ldpp_dout(dpp, 0) << "ERROR: daos_cont_open failed: " << ret << dendl;
    return -ENONET;
  }
  
  bufferlist bl;
  struct DaosBucketInfo dbinfo;
  dbinfo.info = info;
  dbinfo.bucket_attrs = attrs;
  dbinfo.mtime = _mtime;
  dbinfo.bucket_version = bucket_version;
  dbinfo.encode(bl);

  char const *const names[] = {"rgw_info"};
  void const *const values[] = {bl.c_str()}
  size_t const sizes[] = {bl.length()}
  ret = daos_cont_set_attr(coh, 1, names, values, sizes, nullptr);
  if (ret < 0) {
    ldpp_dout(dpp, 0) << "ERROR: daos_cont_set_attr failed: " << ret << dendl;
  }

  return ret;
}

int DaosBucket::load_bucket(const DoutPrefixProvider* dpp, optional_yield y) {
  int ret = refresh_handle();
  if (ret < 0) {
    return -ENONET;
  }
  return 0;
}

/* stats - Not for first pass */
int DaosBucket::read_stats(const DoutPrefixProvider* dpp, int shard_id,
                           std::string* bucket_ver, std::string* master_ver,
                           std::map<RGWObjCategory, RGWStorageStats>& stats,
                           std::string* max_marker, bool* syncstopped) {
  return 0;
}

int DaosBucket::read_stats_async(const DoutPrefixProvider* dpp, int shard_id,
                                 RGWGetBucketStats_CB* ctx) {
  return 0;
}

int DaosBucket::sync_user_stats(const DoutPrefixProvider* dpp,
                                optional_yield y) {
  return 0;
}

int DaosBucket::update_container_stats(const DoutPrefixProvider* dpp) {
  return 0;
}

int DaosBucket::check_bucket_shards(const DoutPrefixProvider* dpp) { return 0; }

int DaosBucket::chown(const DoutPrefixProvider* dpp, User* new_user,
                      User* old_user, optional_yield y,
                      const std::string* marker) {
  /* XXX: Update policies of all the bucket->objects with new user */
  return 0;
}

/* Make sure to call load_bucket() if you need it first */
bool DaosBucket::is_owner(User* user) {
  return (info.owner.compare(user->get_id()) == 0);
}

int DaosBucket::check_empty(const DoutPrefixProvider* dpp, optional_yield y) {
  /* XXX: Check if bucket contains any objects */
  return 0;
}

int DaosBucket::check_quota(const DoutPrefixProvider* dpp,
                            RGWQuotaInfo& user_quota,
                            RGWQuotaInfo& bucket_quota, uint64_t obj_size,
                            optional_yield y, bool check_size_only) {
  /* Not Handled in the first pass as stats are also needed */
  return 0;
}

int DaosBucket::merge_and_store_attrs(const DoutPrefixProvider* dpp,
                                      Attrs& new_attrs, optional_yield y) {
  int ret = Bucket::merge_and_store_attrs(dpp, new_attrs, y);

  /* XXX: handle has_instance_obj like in set_bucket_instance_attrs() */

  return ret;
}

int DaosBucket::try_refresh_info(const DoutPrefixProvider* dpp,
                                 ceph::real_time* pmtime) {
  return 0;
}

/* XXX: usage and stats not supported in the first pass */
int DaosBucket::read_usage(const DoutPrefixProvider* dpp, uint64_t start_epoch,
                           uint64_t end_epoch, uint32_t max_entries,
                           bool* is_truncated, RGWUsageIter& usage_iter,
                           map<rgw_user_bucket, rgw_usage_log_entry>& usage) {
  return 0;
}

int DaosBucket::trim_usage(const DoutPrefixProvider* dpp, uint64_t start_epoch,
                           uint64_t end_epoch) {
  return 0;
}

int DaosBucket::remove_objs_from_index(
    const DoutPrefixProvider* dpp,
    std::list<rgw_obj_index_key>& objs_to_unlink) {
  /* XXX: CHECK: Unlike RadosStore, there is no seperate bucket index table.
   * Delete all the object in the list from the object table of this
   * bucket
   */
  return 0;
}

int DaosBucket::check_index(
    const DoutPrefixProvider* dpp,
    std::map<RGWObjCategory, RGWStorageStats>& existing_stats,
    std::map<RGWObjCategory, RGWStorageStats>& calculated_stats) {
  /* XXX: stats not supported yet */
  return 0;
}

int DaosBucket::rebuild_index(const DoutPrefixProvider* dpp) {
  /* there is no index table in dbstore. Not applicable */
  return 0;
}

int DaosBucket::set_tag_timeout(const DoutPrefixProvider* dpp,
                                uint64_t timeout) {
  /* XXX: CHECK: set tag timeout for all the bucket objects? */
  return 0;
}

int DaosBucket::purge_instance(const DoutPrefixProvider* dpp) {
  /* XXX: CHECK: for dbstore only single instance supported.
   * Remove all the objects for that instance? Anything extra needed?
   */
  return 0;
}

int DaosBucket::set_acl(const DoutPrefixProvider* dpp,
                        RGWAccessControlPolicy& acl, optional_yield y) {
  int ret = 0;
  bufferlist aclbl;

  acls = acl;
  acl.encode(aclbl);

  Attrs attrs = get_attrs();
  attrs[RGW_ATTR_ACL] = aclbl;

  return ret;
}

std::unique_ptr<Object> DaosBucket::get_object(const rgw_obj_key& k) {
  return std::make_unique<DaosObject>(this->store, k, this);
}

int DaosBucket::list(const DoutPrefixProvider* dpp, ListParams& params, int max,
                     ListResults& results, optional_yield y) {
  vector<string> keys(max);
  vector<bufferlist> vals(max);

  ldpp_dout(dpp, 20) << "bucket=" << info.bucket.name
                     << " prefix=" << params.prefix
                     << " marker=" << params.marker << " max=" << max << dendl;

  return 0;
}

int DaosBucket::list_multiparts(
    const DoutPrefixProvider* dpp, const string& prefix, string& marker,
    const string& delim, const int& max_uploads,
    vector<std::unique_ptr<MultipartUpload>>& uploads,
    map<string, bool>* common_prefixes, bool* is_truncated) {
  return 0;
}

int DaosBucket::abort_multiparts(const DoutPrefixProvider* dpp,
                                 CephContext* cct) {
  return 0;
}

void DaosStore::finalize(void) {
  int rc;
  if (daos_handle_is_valid(poh)) {
    rc = daos_pool_disconnect(poh, NULL);
    if (rc != 0) {
      ldout(cctx, 0) << "ERROR: daos_pool_disconnect() failed: " << rc << dendl;
    }
  }

  rc = daos_fini();
  if (rc != 0) {
    ldout(cctx, 0) << "ERROR: daos_fini() failed: " << rc << dendl;
  }
}

const RGWZoneGroup& DaosZone::get_zonegroup() { return *zonegroup; }

int DaosZone::get_zonegroup(const std::string& id, RGWZoneGroup& zg) {
  /* XXX: for now only one zonegroup supported */
  zg = *zonegroup;
  return 0;
}

const RGWZoneParams& DaosZone::get_params() { return *zone_params; }

const rgw_zone_id& DaosZone::get_id() { return cur_zone_id; }

const RGWRealm& DaosZone::get_realm() { return *realm; }

const std::string& DaosZone::get_name() const {
  return zone_params->get_name();
}

bool DaosZone::is_writeable() { return true; }

bool DaosZone::get_redirect_endpoint(std::string* endpoint) { return false; }

bool DaosZone::has_zonegroup_api(const std::string& api) const { return false; }

const std::string& DaosZone::get_current_period_id() {
  return current_period->get_id();
}

std::unique_ptr<LuaScriptManager> DaosStore::get_lua_script_manager() {
  return std::make_unique<DaosLuaScriptManager>(this);
}

int DaosObject::get_obj_state(const DoutPrefixProvider* dpp, RGWObjectCtx* rctx,
                              RGWObjState** _state, optional_yield y,
                              bool follow_olh) {
  return 0;
}

DaosObject::~DaosObject() { delete state; }

//  int DaosObject::read_attrs(const DoutPrefixProvider* dpp, Daos::Object::Read
//  &read_op, optional_yield y, rgw_obj* target_obj)
//  {
//    read_op.params.attrs = &attrs;
//    read_op.params.target_obj = target_obj;
//    read_op.params.obj_size = &obj_size;
//    read_op.params.lastmod = &mtime;
//
//    return read_op.prepare(dpp);
//  }

int DaosObject::set_obj_attrs(const DoutPrefixProvider* dpp, RGWObjectCtx* rctx,
                              Attrs* setattrs, Attrs* delattrs,
                              optional_yield y, rgw_obj* target_obj) {
  ldpp_dout(dpp, 20) << "DEBUG: DaosObject::set_obj_attrs()" << dendl;
  return 0;
}

int DaosObject::get_obj_attrs(RGWObjectCtx* rctx, optional_yield y,
                              const DoutPrefixProvider* dpp,
                              rgw_obj* target_obj) {
  return 0;
}

int DaosObject::modify_obj_attrs(RGWObjectCtx* rctx, const char* attr_name,
                                 bufferlist& attr_val, optional_yield y,
                                 const DoutPrefixProvider* dpp) {
  rgw_obj target = get_obj();
  int r = get_obj_attrs(rctx, y, dpp, &target);
  if (r < 0) {
    return r;
  }
  set_atomic(rctx);
  attrs[attr_name] = attr_val;
  return set_obj_attrs(dpp, rctx, &attrs, nullptr, y, &target);
}

int DaosObject::delete_obj_attrs(const DoutPrefixProvider* dpp,
                                 RGWObjectCtx* rctx, const char* attr_name,
                                 optional_yield y) {
  rgw_obj target = get_obj();
  Attrs rmattr;
  bufferlist bl;

  set_atomic(rctx);
  rmattr[attr_name] = bl;
  return set_obj_attrs(dpp, rctx, nullptr, &rmattr, y, &target);
}

/* RGWObjectCtx will be moved out of sal */
/* XXX: Placeholder. Should not be needed later after Dan's patch */
void DaosObject::set_atomic(RGWObjectCtx* rctx) const { return; }

/* RGWObjectCtx will be moved out of sal */
/* XXX: Placeholder. Should not be needed later after Dan's patch */
void DaosObject::set_prefetch_data(RGWObjectCtx* rctx) { return; }

/* RGWObjectCtx will be moved out of sal */
/* XXX: Placeholder. Should not be needed later after Dan's patch */
void DaosObject::set_compressed(RGWObjectCtx* rctx) { return; }

bool DaosObject::is_expired() { return false; }

// Taken from rgw_rados.cc
void DaosObject::gen_rand_obj_instance_name() {
#define OBJ_INSTANCE_LEN 32
  char buf[OBJ_INSTANCE_LEN + 1];

  gen_rand_alphanumeric_no_underscore(store->ctx(), buf, OBJ_INSTANCE_LEN);
  key.set_instance(buf);
}

int DaosObject::omap_get_vals(const DoutPrefixProvider* dpp,
                              const std::string& marker, uint64_t count,
                              std::map<std::string, bufferlist>* m, bool* pmore,
                              optional_yield y) {
  return 0;
}

int DaosObject::omap_get_all(const DoutPrefixProvider* dpp,
                             std::map<std::string, bufferlist>* m,
                             optional_yield y) {
  return 0;
}

int DaosObject::omap_get_vals_by_keys(const DoutPrefixProvider* dpp,
                                      const std::string& oid,
                                      const std::set<std::string>& keys,
                                      Attrs* vals) {
  return 0;
}

int DaosObject::omap_set_val_by_key(const DoutPrefixProvider* dpp,
                                    const std::string& key, bufferlist& val,
                                    bool must_exist, optional_yield y) {
  return 0;
}

MPSerializer* DaosObject::get_serializer(const DoutPrefixProvider* dpp,
                                         const std::string& lock_name) {
  return new MPDaosSerializer(dpp, store, this, lock_name);
}

int DaosObject::transition(RGWObjectCtx& rctx, Bucket* bucket,
                           const rgw_placement_rule& placement_rule,
                           const real_time& mtime, uint64_t olh_epoch,
                           const DoutPrefixProvider* dpp, optional_yield y) {
  return 0;
}

bool DaosObject::placement_rules_match(rgw_placement_rule& r1,
                                       rgw_placement_rule& r2) {
  /* XXX: support single default zone and zonegroup for now */
  return true;
}

int DaosObject::dump_obj_layout(const DoutPrefixProvider* dpp, optional_yield y,
                                Formatter* f, RGWObjectCtx* obj_ctx) {
  return 0;
}

std::unique_ptr<Object::ReadOp> DaosObject::get_read_op(RGWObjectCtx* ctx) {
  return std::make_unique<DaosObject::DaosReadOp>(this, ctx);
}

DaosObject::DaosReadOp::DaosReadOp(DaosObject* _source, RGWObjectCtx* _rctx)
    : source(_source), rctx(_rctx) {}

int DaosObject::DaosReadOp::prepare(optional_yield y,
                                    const DoutPrefixProvider* dpp) {
  ldpp_dout(dpp, 20) << __func__
                     << ": bucket=" << source->get_bucket()->get_name()
                     << dendl;

  return 0;
}

int DaosObject::DaosReadOp::read(int64_t off, int64_t end, bufferlist& bl,
                                 optional_yield y,
                                 const DoutPrefixProvider* dpp) {
  ldpp_dout(dpp, 20) << "DaosReadOp::read(): sync read." << dendl;
  return 0;
}

// RGWGetObj::execute() calls ReadOp::iterate() to read object from 'off' to
// 'end'. The returned data is processed in 'cb' which is a chain of
// post-processing filters such as decompression, de-encryption and sending back
// data to client (RGWGetObj_CB::handle_dta which in turn calls
// RGWGetObj::get_data_cb() to send data back.).
//
// POC implements a simple sync version of iterate() function in which it reads
// a block of data each time and call 'cb' for post-processing.
int DaosObject::DaosReadOp::iterate(const DoutPrefixProvider* dpp, int64_t off,
                                    int64_t end, RGWGetDataCB* cb,
                                    optional_yield y) {
  return 0;
}

int DaosObject::DaosReadOp::get_attr(const DoutPrefixProvider* dpp,
                                     const char* name, bufferlist& dest,
                                     optional_yield y) {
  // return 0;
  return -ENODATA;
}

std::unique_ptr<Object::DeleteOp> DaosObject::get_delete_op(RGWObjectCtx* ctx) {
  return std::make_unique<DaosObject::DaosDeleteOp>(this, ctx);
}

DaosObject::DaosDeleteOp::DaosDeleteOp(DaosObject* _source, RGWObjectCtx* _rctx)
    : source(_source), rctx(_rctx) {}

// Implementation of DELETE OBJ also requires DaosObject::get_obj_state()
// to retrieve and set object's state from object's metadata.
//
// TODO:
// 1. The POC only remove the object's entry from bucket index and delete
// corresponding Daos objects. It doesn't handle the DeleteOp::params.
// Delete::delete_obj() in rgw_rados.cc shows how rados backend process the
// params.
// 2. Delete an object when its versioning is turned on.
int DaosObject::DaosDeleteOp::delete_obj(const DoutPrefixProvider* dpp,
                                         optional_yield y) {
  ldpp_dout(dpp, 20) << "delete " << source->get_key().to_str() << " from "
                     << source->get_bucket()->get_name() << dendl;
  return 0;
}

int DaosObject::delete_object(const DoutPrefixProvider* dpp,
                              RGWObjectCtx* obj_ctx, optional_yield y,
                              bool prevent_versioning) {
  DaosObject::DaosDeleteOp del_op(this, obj_ctx);
  del_op.params.bucket_owner = bucket->get_info().owner;
  del_op.params.versioning_status = bucket->get_info().versioning_status();

  return del_op.delete_obj(dpp, y);
}

int DaosObject::delete_obj_aio(const DoutPrefixProvider* dpp,
                               RGWObjState* astate, Completions* aio,
                               bool keep_index_consistent, optional_yield y) {
  /* XXX: Make it async */
  return 0;
}

int DaosObject::copy_object(
    RGWObjectCtx& obj_ctx, User* user, req_info* info,
    const rgw_zone_id& source_zone, rgw::sal::Object* dest_object,
    rgw::sal::Bucket* dest_bucket, rgw::sal::Bucket* src_bucket,
    const rgw_placement_rule& dest_placement, ceph::real_time* src_mtime,
    ceph::real_time* mtime, const ceph::real_time* mod_ptr,
    const ceph::real_time* unmod_ptr, bool high_precision_time,
    const char* if_match, const char* if_nomatch, AttrsMod attrs_mod,
    bool copy_if_newer, Attrs& attrs, RGWObjCategory category,
    uint64_t olh_epoch, boost::optional<ceph::real_time> delete_at,
    std::string* version_id, std::string* tag, std::string* etag,
    void (*progress_cb)(off_t, void*), void* progress_data,
    const DoutPrefixProvider* dpp, optional_yield y) {
  return 0;
}

int DaosObject::swift_versioning_restore(RGWObjectCtx* obj_ctx, bool& restored,
                                         const DoutPrefixProvider* dpp) {
  return 0;
}

int DaosObject::swift_versioning_copy(RGWObjectCtx* obj_ctx,
                                      const DoutPrefixProvider* dpp,
                                      optional_yield y) {
  return 0;
}

DaosAtomicWriter::DaosAtomicWriter(
    const DoutPrefixProvider* dpp, optional_yield y,
    std::unique_ptr<rgw::sal::Object> _head_obj, DaosStore* _store,
    const rgw_user& _owner, RGWObjectCtx& obj_ctx,
    const rgw_placement_rule* _ptail_placement_rule, uint64_t _olh_epoch,
    const std::string& _unique_tag)
    : Writer(dpp, y), store(_store) {}

static const unsigned MAX_BUFVEC_NR = 256;

int DaosAtomicWriter::prepare(optional_yield y) { return 0; }

// Accumulate enough data first to make a reasonable decision about the
// optimal unit size for a new object, or bs for existing object (32M seems
// enough for 4M units in 8+2 parity groups, a common config on wide pools),
// and then launch the write operations.
int DaosAtomicWriter::process(bufferlist&& data, uint64_t offset) { return 0; }

int DaosAtomicWriter::complete(
    size_t accounted_size, const std::string& etag, ceph::real_time* mtime,
    ceph::real_time set_mtime, std::map<std::string, bufferlist>& attrs,
    ceph::real_time delete_at, const char* if_match, const char* if_nomatch,
    const std::string* user_data, rgw_zone_set* zones_trace, bool* canceled,
    optional_yield y) {
  return 0;
}

int DaosMultipartUpload::delete_parts(const DoutPrefixProvider* dpp) {
  return 0;
}

int DaosMultipartUpload::abort(const DoutPrefixProvider* dpp, CephContext* cct,
                               RGWObjectCtx* obj_ctx) {
  return 0;
}

std::unique_ptr<rgw::sal::Object> DaosMultipartUpload::get_meta_obj() {
  return nullptr;
}

int DaosMultipartUpload::init(const DoutPrefixProvider* dpp, optional_yield y,
                              RGWObjectCtx* obj_ctx, ACLOwner& _owner,
                              rgw_placement_rule& dest_placement,
                              rgw::sal::Attrs& attrs) {
  return 0;
}

int DaosMultipartUpload::list_parts(const DoutPrefixProvider* dpp,
                                    CephContext* cct, int num_parts, int marker,
                                    int* next_marker, bool* truncated,
                                    bool assume_unsorted) {
  return 0;
}

int DaosMultipartUpload::complete(
    const DoutPrefixProvider* dpp, optional_yield y, CephContext* cct,
    map<int, string>& part_etags, list<rgw_obj_index_key>& remove_objs,
    uint64_t& accounted_size, bool& compressed, RGWCompressionInfo& cs_info,
    off_t& off, std::string& tag, ACLOwner& owner, uint64_t olh_epoch,
    rgw::sal::Object* target_obj, RGWObjectCtx* obj_ctx) {
  return 0;
}

int DaosMultipartUpload::get_info(const DoutPrefixProvider* dpp,
                                  optional_yield y, RGWObjectCtx* obj_ctx,
                                  rgw_placement_rule** rule,
                                  rgw::sal::Attrs* attrs) {
  return 0;
}

std::unique_ptr<Writer> DaosMultipartUpload::get_writer(
    const DoutPrefixProvider* dpp, optional_yield y,
    std::unique_ptr<rgw::sal::Object> _head_obj, const rgw_user& owner,
    RGWObjectCtx& obj_ctx, const rgw_placement_rule* ptail_placement_rule,
    uint64_t part_num, const std::string& part_num_str) {
  return std::make_unique<DaosMultipartWriter>(
      dpp, y, this, std::move(_head_obj), store, owner, obj_ctx,
      ptail_placement_rule, part_num, part_num_str);
}

int DaosMultipartWriter::prepare(optional_yield y) { return 0; }

int DaosMultipartWriter::process(bufferlist&& data, uint64_t offset) {
  return 0;
}

int DaosMultipartWriter::complete(
    size_t accounted_size, const std::string& etag, ceph::real_time* mtime,
    ceph::real_time set_mtime, std::map<std::string, bufferlist>& attrs,
    ceph::real_time delete_at, const char* if_match, const char* if_nomatch,
    const std::string* user_data, rgw_zone_set* zones_trace, bool* canceled,
    optional_yield y) {
  return 0;
}

std::unique_ptr<RGWRole> DaosStore::get_role(
    std::string name, std::string tenant, std::string path,
    std::string trust_policy, std::string max_session_duration_str,
    std::multimap<std::string, std::string> tags) {
  RGWRole* p = nullptr;
  return std::unique_ptr<RGWRole>(p);
}

std::unique_ptr<RGWRole> DaosStore::get_role(std::string id) {
  RGWRole* p = nullptr;
  return std::unique_ptr<RGWRole>(p);
}

int DaosStore::get_roles(const DoutPrefixProvider* dpp, optional_yield y,
                         const std::string& path_prefix,
                         const std::string& tenant,
                         vector<std::unique_ptr<RGWRole>>& roles) {
  return 0;
}

std::unique_ptr<RGWOIDCProvider> DaosStore::get_oidc_provider() {
  RGWOIDCProvider* p = nullptr;
  return std::unique_ptr<RGWOIDCProvider>(p);
}

int DaosStore::get_oidc_providers(
    const DoutPrefixProvider* dpp, const std::string& tenant,
    vector<std::unique_ptr<RGWOIDCProvider>>& providers) {
  return 0;
}

std::unique_ptr<MultipartUpload> DaosBucket::get_multipart_upload(
    const std::string& oid, std::optional<std::string> upload_id,
    ACLOwner owner, ceph::real_time mtime) {
  return std::make_unique<DaosMultipartUpload>(store, this, oid, upload_id,
                                               owner, mtime);
}

std::unique_ptr<Writer> DaosStore::get_append_writer(
    const DoutPrefixProvider* dpp, optional_yield y,
    std::unique_ptr<rgw::sal::Object> _head_obj, const rgw_user& owner,
    RGWObjectCtx& obj_ctx, const rgw_placement_rule* ptail_placement_rule,
    const std::string& unique_tag, uint64_t position,
    uint64_t* cur_accounted_size) {
  return nullptr;
}

std::unique_ptr<Writer> DaosStore::get_atomic_writer(
    const DoutPrefixProvider* dpp, optional_yield y,
    std::unique_ptr<rgw::sal::Object> _head_obj, const rgw_user& owner,
    RGWObjectCtx& obj_ctx, const rgw_placement_rule* ptail_placement_rule,
    uint64_t olh_epoch, const std::string& unique_tag) {
  return std::make_unique<DaosAtomicWriter>(
      dpp, y, std::move(_head_obj), this, owner, obj_ctx, ptail_placement_rule,
      olh_epoch, unique_tag);
}

std::unique_ptr<User> DaosStore::get_user(const rgw_user& u) {
  ldout(cctx, 20) << "bucket's user:  " << u.to_str() << dendl;
  return std::make_unique<DaosUser>(this, u);
}

int DaosStore::get_user_by_access_key(const DoutPrefixProvider* dpp,
                                      const std::string& key, optional_yield y,
                                      std::unique_ptr<User>* user) {
  RGWUserInfo uinfo;
  User* u;
  RGWObjVersionTracker objv_tracker;

  /* Hard code user info for test. */
  rgw_user testid_user("tenant", "tester", "ns");
  uinfo.user_id = testid_user;
  uinfo.display_name = "Daos Explorer";
  uinfo.user_email = "tester@seagate.com";
  RGWAccessKey k1("0555b35654ad1656d804",
                  "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==");
  uinfo.access_keys["0555b35654ad1656d804"] = k1;

  u = new DaosUser(this, uinfo);
  if (!u) return -ENOMEM;

  u->get_version_tracker() = objv_tracker;
  user->reset(u);

  return 0;
}

int DaosStore::get_user_by_email(const DoutPrefixProvider* dpp,
                                 const std::string& email, optional_yield y,
                                 std::unique_ptr<User>* user) {
  RGWUserInfo uinfo;
  User* u;
  RGWObjVersionTracker objv_tracker;

  /* Hard code user info for test. */
  rgw_user testid_user("tenant", "tester", "ns");
  uinfo.user_id = testid_user;
  uinfo.display_name = "Daos Explorer";
  uinfo.user_email = "tester@seagate.com";
  RGWAccessKey k1("0555b35654ad1656d804",
                  "h7GhxuBLTrlhVUyxSPUKUV8r/2EI4ngqJxD7iBdBYLhwluN30JaT3Q==");
  uinfo.access_keys["0555b35654ad1656d804"] = k1;

  u = new DaosUser(this, uinfo);
  if (!u) return -ENOMEM;

  u->get_version_tracker() = objv_tracker;
  user->reset(u);
  return 0;
}

int DaosStore::get_user_by_swift(const DoutPrefixProvider* dpp,
                                 const std::string& user_str, optional_yield y,
                                 std::unique_ptr<User>* user) {
  /* Swift keys and subusers are not supported for now */
  return 0;
}

std::unique_ptr<Object> DaosStore::get_object(const rgw_obj_key& k) {
  return std::make_unique<DaosObject>(this, k);
}

int DaosStore::get_bucket(const DoutPrefixProvider* dpp, User* u,
                          const rgw_bucket& b, std::unique_ptr<Bucket>* bucket,
                          optional_yield y) {
  int ret;
  Bucket* bp;

  bp = new DaosBucket(this, b, u);
  ret = bp->load_bucket(dpp, y);
  if (ret < 0) {
    delete bp;
    return ret;
  }

  bucket->reset(bp);
  return 0;
}

int DaosStore::get_bucket(User* u, const RGWBucketInfo& i,
                          std::unique_ptr<Bucket>* bucket) {
  Bucket* bp;

  bp = new DaosBucket(this, i, u);
  /* Don't need to fetch the bucket info, use the provided one */

  bucket->reset(bp);
  return 0;
}

int DaosStore::get_bucket(const DoutPrefixProvider* dpp, User* u,
                          const std::string& tenant, const std::string& name,
                          std::unique_ptr<Bucket>* bucket, optional_yield y) {
  rgw_bucket b;

  b.tenant = tenant;
  b.name = name;

  return get_bucket(dpp, u, b, bucket, y);
}

bool DaosStore::is_meta_master() { return true; }

int DaosStore::forward_request_to_master(const DoutPrefixProvider* dpp,
                                         User* user, obj_version* objv,
                                         bufferlist& in_data, JSONParser* jp,
                                         req_info& info, optional_yield y) {
  return 0;
}

std::string DaosStore::zone_unique_id(uint64_t unique_num) { return ""; }

std::string DaosStore::zone_unique_trans_id(const uint64_t unique_num) {
  return "";
}

int DaosStore::cluster_stat(RGWClusterStat& stats) { return 0; }

std::unique_ptr<Lifecycle> DaosStore::get_lifecycle(void) { return 0; }

std::unique_ptr<Completions> DaosStore::get_completions(void) { return 0; }

std::unique_ptr<Notification> DaosStore::get_notification(
    rgw::sal::Object* obj, struct req_state* s,
    rgw::notify::EventType event_type, const std::string* object_name) {
  return std::make_unique<DaosNotification>(obj, event_type);
}

int DaosStore::log_usage(const DoutPrefixProvider* dpp,
                         map<rgw_user_bucket, RGWUsageBatch>& usage_info) {
  return 0;
}

int DaosStore::log_op(const DoutPrefixProvider* dpp, string& oid,
                      bufferlist& bl) {
  return 0;
}

int DaosStore::register_to_service_map(const DoutPrefixProvider* dpp,
                                       const string& daemon_type,
                                       const map<string, string>& meta) {
  return 0;
}

void DaosStore::get_quota(RGWQuotaInfo& bucket_quota,
                          RGWQuotaInfo& user_quota) {
  // XXX: Not handled for the first pass
  return;
}

int DaosStore::set_buckets_enabled(const DoutPrefixProvider* dpp,
                                   vector<rgw_bucket>& buckets, bool enabled) {
  return 0;
}

int DaosStore::get_sync_policy_handler(const DoutPrefixProvider* dpp,
                                       std::optional<rgw_zone_id> zone,
                                       std::optional<rgw_bucket> bucket,
                                       RGWBucketSyncPolicyHandlerRef* phandler,
                                       optional_yield y) {
  return 0;
}

RGWDataSyncStatusManager* DaosStore::get_data_sync_manager(
    const rgw_zone_id& source_zone) {
  return 0;
}

int DaosStore::read_all_usage(
    const DoutPrefixProvider* dpp, uint64_t start_epoch, uint64_t end_epoch,
    uint32_t max_entries, bool* is_truncated, RGWUsageIter& usage_iter,
    map<rgw_user_bucket, rgw_usage_log_entry>& usage) {
  return 0;
}

int DaosStore::trim_all_usage(const DoutPrefixProvider* dpp,
                              uint64_t start_epoch, uint64_t end_epoch) {
  return 0;
}

int DaosStore::get_config_key_val(string name, bufferlist* bl) { return 0; }

int DaosStore::meta_list_keys_init(const DoutPrefixProvider* dpp,
                                   const string& section, const string& marker,
                                   void** phandle) {
  return 0;
}

int DaosStore::meta_list_keys_next(const DoutPrefixProvider* dpp, void* handle,
                                   int max, list<string>& keys,
                                   bool* truncated) {
  return 0;
}

void DaosStore::meta_list_keys_complete(void* handle) { return; }

std::string DaosStore::meta_get_marker(void* handle) { return ""; }

int DaosStore::meta_remove(const DoutPrefixProvider* dpp, string& metadata_key,
                           optional_yield y) {
  return 0;
}

std::string DaosStore::get_cluster_id(const DoutPrefixProvider* dpp,
                                      optional_yield y) {
  return "";
}

}  // namespace rgw::sal

extern "C" {

void* newDaosStore(CephContext* cct) {
  int rc = -1;
  rgw::sal::DaosStore* store = new rgw::sal::DaosStore(cct);

  if (store) {
    rc = daos_init();

    // DAOS init failed, allow the case where init is already done
    if (rc != 0 && rc != DER_ALREADY) {
      ldout(cct, 0) << "ERROR: daos_init() failed: " << rc << dendl;
      goto err;
    }

    // XXX: these params should be taken from config settings and
    // cct somehow?
    const auto& daos_pool = g_conf().get_val<std::string>("daos_pool");
    ldout(cct, 0) << "INFO: daos pool: " << daos_pool << dendl;
    daos_pool_info_t pool_info = {};
    rc = daos_pool_connect(daos_pool.c_str(), nullptr, DAOS_PC_RO,
                           &store->poh, &pool_info, nullptr);

    if (rc != 0) {
      ldout(cct, 0) << "ERROR: daos_pool_connect() failed: " << rc << dendl;
      goto err_fini;
    }

    uuid_copy(store->pool, pool_info.pi_uuid);
  }

  return store;
err_fini:
  daos_fini();
err:
  delete store;
  return nullptr;
}
}
