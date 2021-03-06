/*---------------------------------------------------------------------------
   Copyright (c) 2019 The b0 programmers. All rights reserved.
   Distributed under the ISC license, see license at the end of the file.
   %%NAME%% release %%VERSION%%
   --------------------------------------------------------------------------*/

#include "b00_stubs.h"

/* Portable cpu information */

/* Darwin and POSIX */

#if defined(OCAML_B00_DARWIN) || defined(OCAML_B00_POSIX)

#include <unistd.h>

CAMLprim value ocaml_b00_cpu_logical_count (value unit)
{
  int n = sysconf (_SC_NPROCESSORS_ONLN);
  if (n < 0) { n = 1; }
  return Val_int (n);
}

/* Windows */

#elif defined(OCAML_B00_WINDOWS)

#include <windows.h>

CAMLPrim value ocaml_b00_cpu_logical_count (value unit)
{
  SYSTEM_INFO i;
  GetSystemInfo (&i);
  DWORD n = i.dwNumberOfProcessors;
  if (n < 0) { n = 1; }
  return Val_int (n);
}

/* Unsupported */

#else
#warning OCaml B00 library: unsupported platform, cpu count will always be 1

CAMLPrim value ocaml_b00_cpu_logical_count (value unit)
{
  return Val_int (1);
}
#endif

/*---------------------------------------------------------------------------
   Copyright (c) 2019 The b0 programmers

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*/
