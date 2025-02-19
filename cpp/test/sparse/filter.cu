/*
 * Copyright (c) 2019-2023, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "../test_utils.cuh"
#include <gtest/gtest.h>
#include <raft/util/cudart_utils.hpp>

#include <raft/random/rng.cuh>
#include <raft/sparse/coo.hpp>
#include <raft/sparse/op/filter.cuh>
#include <raft/sparse/op/sort.cuh>

#include <iostream>

namespace raft {
namespace sparse {

template <typename T>
struct SparseFilterInputs {
  int m, n, nnz;
  unsigned long long int seed;
};

template <typename T>
class SparseFilterTests : public ::testing::TestWithParam<SparseFilterInputs<T>> {
 protected:
  void SetUp() override {}

  void TearDown() override {}

 protected:
  SparseFilterInputs<T> params;
};

const std::vector<SparseFilterInputs<float>> inputsf = {{5, 10, 5, 1234ULL}};

typedef SparseFilterTests<float> COORemoveZeros;
TEST_P(COORemoveZeros, Result)
{
  raft::device_resources h;
  auto stream = h.get_stream();
  params      = ::testing::TestWithParam<SparseFilterInputs<float>>::GetParam();

  float* in_h_vals = new float[params.nnz];

  COO<float> in(stream, params.nnz, 5, 5);

  raft::random::RngState r(params.seed);
  uniform(h, r, in.vals(), params.nnz, float(-1.0), float(1.0));

  raft::update_host(in_h_vals, in.vals(), params.nnz, stream);

  in_h_vals[0] = 0;
  in_h_vals[2] = 0;
  in_h_vals[3] = 0;

  int* in_h_rows = new int[params.nnz];
  int* in_h_cols = new int[params.nnz];

  for (int i = 0; i < params.nnz; i++) {
    in_h_rows[i] = params.nnz - i - 1;
    in_h_cols[i] = i;
  }

  raft::update_device(in.rows(), in_h_rows, params.nnz, stream);
  raft::update_device(in.cols(), in_h_cols, params.nnz, stream);
  raft::update_device(in.vals(), in_h_vals, params.nnz, stream);

  op::coo_sort<float>(&in, stream);

  int out_rows_ref_h[2] = {0, 3};
  int out_cols_ref_h[2] = {4, 1};

  float* out_vals_ref_h = (float*)malloc(2 * sizeof(float));
  out_vals_ref_h[0]     = in_h_vals[4];
  out_vals_ref_h[1]     = in_h_vals[1];

  COO<float> out_ref(stream, 2, 5, 5);
  COO<float> out(stream);

  raft::update_device(out_ref.rows(), *&out_rows_ref_h, 2, stream);
  raft::update_device(out_ref.cols(), *&out_cols_ref_h, 2, stream);
  raft::update_device(out_ref.vals(), out_vals_ref_h, 2, stream);

  op::coo_remove_zeros<float>(&in, &out, stream);
  RAFT_CUDA_TRY(cudaStreamSynchronize(stream));

  ASSERT_TRUE(raft::devArrMatch<int>(out_ref.rows(), out.rows(), 2, raft::Compare<int>()));
  ASSERT_TRUE(raft::devArrMatch<int>(out_ref.cols(), out.cols(), 2, raft::Compare<int>()));
  ASSERT_TRUE(raft::devArrMatch<float>(out_ref.vals(), out.vals(), 2, raft::Compare<float>()));

  free(out_vals_ref_h);

  delete[] in_h_rows;
  delete[] in_h_cols;
  delete[] in_h_vals;
}

INSTANTIATE_TEST_CASE_P(SparseFilterTests, COORemoveZeros, ::testing::ValuesIn(inputsf));

}  // namespace sparse
}  // namespace raft
