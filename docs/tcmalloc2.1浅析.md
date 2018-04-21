history:

  * version 1.0 done by wertherzhang @2014-05-12 write done with emacs org
  * version 1.1 done by wertherzhang @2017-03-16 moved to leanote


# tcmalloc2.1 浅析

来源: https://pengzhangdev.github.io/tcmalloc2.1%E6%B5%85%E6%9E%90/

## 简介

tcmalloc(thread cached malloc) 是由google为并发程序而开发的内存分配管理器.tcmalloc致力于减少多线程内存请求时对锁的竞争, 在对小内存的申请时,可以在无需锁的情况下高效获取内存;而在获取大内存时,使用高校的spinlocks.正因为tcmalloc是在线程局部空间(TLS)预先存储部分空闲内存用于分配, 在程序刚启动时,其所占用的内存会比dlmalloc或其他的内存管理器更大,但其增长速幅度比其他管理器小,所以,在后期,实际占用内存空间会相接近.

## 原理简析

### overview

![](https://pengzhang.netlify.com/assets/images/tcmalloc2.1浅析-0.png)

tcmalloc为每一个线程分配一个线程本地缓存(Thread Cache, 以下简称TC)．所有小对象(<256K)都会优先从ThreadCache分配．而当ThreadCache没有足够空闲内存时，就会从CentralCache(以下简称CC)申请内存.而当Thread Cache内存富裕时,会将内存返回给Central Cache. Central Cache是以进程为单位存在,ThreadCache是以线程为单位存在.对于大内存(>256K), 直接从Page Heap(以下简称PH)按页对齐(4K)申请.通常情况下,一连串的页面(4k)可以多个小内存序列,每个序列元素等大小.TC, CC, PH 的关系是, TC 向CC申请内存并GC给CC. CC 向PH 申请内存并GC给PH.在TC中的数据单位时字节,按大小为单位分类,每个类中时链表.在PH中的数据单位时Page(4K),按PageNum分类,每个分类内部用链表管理,第PageNum类的链表结点为PageNum个Page.在CC中存在最多的数据结构,它连接着TC和PH.其存放了来自CC的slot结构,和来自PH的PH的span结构.数据的移动. 所有的数据从TC<->CC<->PH都是批量(batch)移动.从TC申请或释放的内存都会优先从CC的slots数组处理.slots存放的就是最近从TC释放的内存,用于快速的TC内存申请.如果slots条件不满足,就会操作CC中的spans对象.所有移动的数据的大小和TC中的最大大小都是在动态调整的.

### 小对象内存分配

![](https://pengzhang.netlify.com/assets/images/tcmalloc2.1浅析-1.png)

上图为小内存管理时的sizemap分类的示意图.小内存的管理都处于ThreadCache中.所有对于256k以下的内存申请都是从TC中获取.个人把小内存分配,理解为3级内存请求.进程向TC请求内存, TC向CC请求内存,CC向PH请求内存.

* 进程向TC请求和释放内存内存
    * TC内存管理
      首先, 在进程空间中,对于每一个线程,存在与其对应的TC, 所有的TC被用链表串联,不属于任何一个线程独有.通过这种,每一个TC都可以看到任何一个TC.如上图,在TC中对内存进行了分类管理,每一个请求的内存大小都会向上取整到对应分类,然后直接从对应的链表中取出一项.
    * 进程向TC申请内存
        * 将请求内存向上对其到size class.
        * 从对应size class中查找空闲内存, 如果存在,直接返回.
        * 如果size class中无空闲内存,则触发向CC请求内存的机制.
    
    * 进程向TC释放内存
        * 从释放内存的地址,查找对应的pageID.
        * 如果page ID 属于TC, 并且TC的Heap存在,则释放到TC中
        * 如果PageID属于TC,而TC的Heap不存在(跨线程内存申请和释放, 申请线程被销毁的情况下),则释放到CC中,参考TC向CC释放内存
        * 如果pageID属于PH中(大内存), 则直接释放到PH中.

* TC向CC请求和释放内存
    * CC的内存管理.
        在CC中同样维护了与TC中对应的分类箱子.每个类别中是一个CentralFreeList类. 该类中维护了一个slots双向链表,用于快速分配内存给CC并接收释放的内存, 其内存粒度与TC中相同.同样,该类中也维护了两个span双向链表,empty(不包含空闲块)和nonempty(包含空闲块).span会在这两个链表中移动.Span是个什么东西呢?它是PH内存管理的一个粒度,其表示的内存大小为page(4K)的倍数.同时,它包含了更小的粒度单位objects. 所以,也可以认为它是CC和PH之间移动的内存单元.所以,Span和slots的关系是,spans可以拆分成slots
        
        这里,我们认为span属于PH的,所以,跟span的相关操作我们在PH讲解.

        ```   
            class CentralFreeList {
               // ...
            
            private:
               //...
            
              // We keep linked lists of empty and non-empty spans.
              size_t   size_class_;     // My size class
              Span     empty_;          // Dummy header for list of empty spans
              Span     nonempty_;       // Dummy header for list of non-empty spans
              size_t   num_spans_;      // Number of spans in empty_ plus nonempty_
              size_t   counter_;        // Number of free objects in cache entry
            
              // Here we reserve space for TCEntry cache slots.  Space is preallocated
              // for the largest possible number of entries than any one size class may
              // accumulate.  Not all size classes are allowed to accumulate
              // kMaxNumTransferEntries, so there is some wasted space for those size
              // classes.
              TCEntry tc_slots_[kMaxNumTransferEntries];
            
              // ...
            };
        
            // Information kept for a span (a contiguous run of pages).
            struct Span {
              PageID        start;          // Starting page number
              Length        length;         // Number of pages in span
              Span*         next;           // Used when in link list
              Span*         prev;           // Used when in link list
              void*         objects;        // Linked list of free objects
              unsigned int  refcount : 16;  // Number of non-free objects // 当refcount为0, 则释放给PageHeap.
              unsigned int  sizeclass : 8;  // Size-class for small objects (or 0)  // 这个是TC的 SizeClass 分类.因为每个分类对应一个CentralFreeList,每个List对应1个slots和2个spans. 所以,spans中的objects都统一属于某个SizeClass, 这里需要维护这个数据对object的.
              unsigned int  location : 2;   // Is the span on a freelist, and if so, which?  // 在empty/nonempty list?
              unsigned int  sample : 1;     // Sampled object?
            
            #undef SPAN_HISTORY
            #ifdef SPAN_HISTORY
              // For debugging, we can keep a log events per span
              int nexthistory;
              char history[64];
              int value[64];
            #endif
            
              // What freelist the span is on: IN_USE if on none, or normal or returned
              enum { IN_USE, ON_NORMAL_FREELIST, ON_RETURNED_FREELIST };
            };
        ```
  
    * TC向CC请求内存
        TC只有在其对应的分类中,不存在空闲块时,才会向CC的对应分类申请batch_size的空闲块.
        
        * 根据当前请求的内存,找到对应的分类,和该分类下的默认CC请求的对象个数(`batch_size`). 在该分类free list的最大长度和`batch_size`中取最小值为需要申请的对象个数(`num_to_move`).
        * 基于慢启动算法,缓慢增加当前分类的free list容量.
        * 从CC的对应分类中的slots对像,获取相应数量的objects.
        * 如果slots不满足,则从spans对象中获取相应的objects.
        * 如果spans不满足(nonempty为NULL),则触发CC向PH请求内存.
        
        ```
            inline void* ThreadCache::Allocate(size_t size, size_t cl) {
              // size 已经被向上对齐, cl为分类的箱号
              ASSERT(size <= kMaxSize);
              // kMaxSzie == 256 * 1024
              ASSERT(size == Static::sizemap()->ByteSizeForClass(cl));
              // sizemap() 为分类的数组.每个成员为链表.
              // ByteSizeForClass是取出对应箱号内的理论内存大小.
            
              // 以上assert 检查,理应在调用该函数之前保证.
            
              FreeList* list = &list_[cl];
              if (list->empty()) {
                return FetchFromCentralCache(cl, size);
              }
              size_ -= size;
              return list->Pop();
            }
        ```
        
        我们重点描述下,TC向CC申请内存的过程.首先,我们需要知道,CC也按照TC的内存分类方式,存在各个分类的箱子.所以,实际上是向CC中的对应分类获取一连串的空闲内存.首先,我们得确定,移动的内存数量,也就是对应分类的内存块个数.默认情况下, 有一个规则确定每个分类对应的该移动的内存数量.以64K为基准,除以对应分类的内存大小,算出来的为移动的内存数量.但是,对于一些极小内存,这个值将很大,所以,我们限制最大为32768个,同理,对于极大内存,这个值<=1,会导致这个分类的内存请求每次都向CC请求,所以,我们这只最小为2,保证最多每2次向CC请求一次内存.下面为,默认的分类和对应的移动数量.
        
| idx | `class_size` | ` num_to_move_objs` |  `num_to_move_pages` |
| --- | --- | --- | --- |
| 1 | 8 | 8192 | 2 |
| 2 | 16 | 4096 | 2 |
| 3 | 32 | 2048 | 2 |
| 4 | 48 | 1365 | 2 |
| 5 | 64 | 1024 | 2 |
| 6 | 80 | 819 | 2 |
| 7 | 96 | 682 | 2 |
| 8 | 112 | 585 | 2 |
| 9 | 128 | 512 | 2 |
| 10 | 144 | 455 | 2 |
| 11 | 160 | 409 | 2 |
| 12 | 176 | 372 | 2 |
| 13 | 192 | 341 | 2 |
| 14 | 208 | 315 | 2 |
| 15 | 224 | 292 | 2 |
| 16 | 240 | 273 | 2 |
| 17 | 256 | 256 | 2 |
| 18 | 288 | 227 | 2 |
| 19 | 320 | 204 | 2 |
| 20 | 352 | 186 | 2 |
| 21 | 384 | 170 | 2 |
| 22 | 416 | 157 | 2 |
| 23 | 448 | 146 | 2 |
| 24 | 480 | 136 | 2 |
| 25 | 512 | 128 | 2 |
| 26 | 576 | 113 | 2 |
| 27 | 640 | 102 | 2 |
| 28 | 704 | 93 | 2 |
| 29 | 768 | 85 | 2 |
| 30 | 832 | 78 | 2 |
| 31 | 896 | 73 | 2 |
| 32 | 960 | 68 | 2 |
| 33 | 1024 | 64 | 2 |
| 34 | 1152 | 56 | 2 |
| 35 | 1280 | 51 | 2 |
| 36 | 1408 | 46 | 2 |
| 37 | 1536 | 42 | 2 |
| 38 | 1792 | 36 | 2 |
| 39 | 2048 | 32 | 2 |
| 40 | 2304 | 28 | 2 |
| 41 | 2560 | 25 | 2 |
| 42 | 2816 | 23 | 3 |
| 43 | 3072 | 21 | 2 |
| 44 | 3328 | 19 | 3 |
| 45 | 4096 | 16 | 2 |
| 46 | 4608 | 14 | 3 |
| 47 | 5120 | 12 | 2 |
| 48 | 6144 | 10 | 3 |
| 49 | 6656 | 9 | 5 |
| 50 | 8192 | 8 | 2 |
| 51 | 9216 | 7 | 5 |
| 52 | 10240 | 6 | 4 |
| 53 | 12288 | 5 | 3 |
| 54 | 13312 | 4 | 5 |
| 55 | 16384 | 4 | 2 |
| 56 | 20480 | 3 | 5 |
| 57 | 24576 | 2 | 3 |
| 58 | 26624 | 2 | 7 |
| 59 | 32768 | 2 | 4 |
| 60 | 40960 | 2 | 5 |
| 61 | 49152 | 2 | 6 |
| 62 | 57344 | 2 | 7 |
| 63 | 65536 | 2 | 8 |
| 64 | 73728 | 2 | 9 |
| 65 | 81920 | 2 | 10 |
| 66 | 90112 | 2 | 11 |
| 67 | 98304 | 2 | 12 |
| 68 | 106496 | 2 | 13 |
| 69 | 114688 | 2 | 14 |
| 70 | 122880 | 2 | 15 |
| 71 | 131072 | 2 | 16 |
| 72 | 139264 | 2 | 17 |
| 73 | 147456 | 2 | 18 |
| 74 | 155648 | 2 | 19 |
| 75 | 163840 | 2 | 20 |
| 76 | 172032 | 2 | 21 |
| 77 | 180224 | 2 | 22 |
| 78 | 188416 | 2 | 23 |
| 79 | 196608 | 2 | 24 |
| 80 | 204800 | 2 | 25 |
| 81 | 212992 | 2 | 26 |
| 82 | 221184 | 2 | 27 |
| 83 | 229376 | 2 | 28 |
| 84 | 237568 | 2 | 29 |
| 85 | 245760 | 2 | 30 |
| 86 | 253952 | 2 | 31 |
| 87 | 262144 | 2 | 32 |

        
        以上只是默认值,这个值是会随着内存申请次数的增加而调整, google给这个算法取名为慢启动(slow-start)算法. 我们来看下.首先, list有个最大值,我们能移动的大小为list最大长度和默认中的最小值. 为了保证,在大量申请时的效率, 在max length < 默认值时,我们慢慢增长max length, 防止浪费空间,又能有效地逐渐提高效率. 在max length > 默认值时,要么时大量请求,要么是由于请求的内存很大,导致默认值小,所以,这个时候,可以每次增加默认值大小.但最大移动数依然时默认的移动数.
        
        ```
            // slow-start
                    (setq batch_size num_to_move)
                    (setq list_length get_list_length_max_length)
                    (fetch-mem (min batch_size list_length))
                    (set-list-max-length 
                            (if (< list_length batch_size)
                                   (+ list_length 1)
                                  (+ list_length batch_size)))
        
            // Remove some objects of class "cl" from central cache and add to thread heap.
            // On success, return the first object for immediate use; otherwise return NULL.
            void* ThreadCache::FetchFromCentralCache(size_t cl, size_t byte_size) {
              FreeList* list = &list_[cl];
              ASSERT(list->empty());
              // batch_size 为默认的移动数量
              const int batch_size = Static::sizemap()->num_objects_to_move(cl);
            
              // 考虑到list的大小,我们取list最大长度和batch_size中的最小值.
              const int num_to_move = min<int>(list->max_length(), batch_size);
              void *start, *end;
              // 从CC获取内存, 只是简单的链表删除操作
              int fetch_count = Static::central_cache()[cl].RemoveRange(
                  &start, &end, num_to_move);
            
              ASSERT((start == NULL) == (fetch_count == 0));
              if (--fetch_count >= 0) {
                // size_为获取到的内存大小
                size_ += byte_size * fetch_count;
                // 添加到单向链表中.链表插入操作.
                list->PushRange(fetch_count, SLL_Next(start), end);
              }
            
              // 如果list的最大长度 < 默认移动长度, 则list最大长度+1, 慢慢靠近默认移动长度.
              if (list->max_length() < batch_size) {
                list->set_max_length(list->max_length() + 1);
              } else {
                // 否则,我们直接增长batch_size 长度, 当然不允许无限增长.
                int new_length = min<int>(list->max_length() + batch_size,
                                          kMaxDynamicFreeListLength);
                // 必须保证max_length 时batch_size的整数倍,这样才能做到在N次batch_size的移动正好释放完list, 而不需要分割.
                new_length -= new_length % batch_size;
                ASSERT(new_length % batch_size == 0);
                list->set_max_length(new_length);
              }
              return start;
            }
        ```
        
        这里实际从CC获取空闲空间的函数是RemoveRange函数.首先常试直接从slots中获取,如果slots不够,则再从spans获取.
        
        ```
            int CentralFreeList::RemoveRange(void **start, void **end, int N) {
              ASSERT(N > 0);
              lock_.Lock();
              if (N == Static::sizemap()->num_objects_to_move(size_class_) &&
                  used_slots_ > 0) {
                int slot = --used_slots_;
                ASSERT(slot >= 0);
                TCEntry *entry = &tc_slots_[slot];
                *start = entry->head;
                *end = entry->tail;
                lock_.Unlock();
                return N;
              }
            
              int result = 0;
              void* head = NULL;
              void* tail = NULL;
              // TODO: Prefetch multiple TCEntries?
              tail = FetchFromSpansSafe();
              if (tail != NULL) {
                SLL_SetNext(tail, NULL);
                head = tail;
                result = 1;
                while (result < N) {
                  void *t = FetchFromSpans();
                  if (!t) break;
                  SLL_Push(&head, t);
                  result++;
                }
              }
              lock_.Unlock();
              *start = head;
              *end = tail;
              return result;
            }
        
            int SizeMap::NumMoveSize(size_t size) {
              if (size == 0) return 0;
            
              int num = static_cast<int>(64.0 * 1024.0 / size);
              if (num < 2) num = 2;
            
              if (num > FLAGS_tcmalloc_transfer_num_objects)
                num = FLAGS_tcmalloc_transfer_num_objects;
            
              return num;
            }
    ```
    
    * TC向CC释放内存
        TC向CC释放内存的条件是,在进程向TC释放内存时,TC对应的分类free list的 `length > max_length` 或者 TC的总 `size > max_size`, 分别触发ListTooLong和Scavenge内存回收.
        
        ListTooLong 回收内存规则:
        
            * 如果 `list length < batch_size` ,则清空链表. 这种情况下,只有非频繁内存请求,才会 `length < batch_size`, 所以, 在时间和空间上,考虑优先空间,释放内存.
            * 如果 `list length > batch_size`, 则释放 `batch_size` 个object.并且减少list的max length, 尽可能利用慢启动, 减少空间浪费的问题.
        
        Scavenge回收内存规则:
        
            * 遍历TC中所有的free list, 将(lowwatermark > 0)的list 释放 (lowwatermark / 2 )个objects.
            * 如果lowwatermark > 0的 `list length > batch_size`, 则更新`max_length` 为 `max_length - batch_size`, 利用慢启动算法,减慢内存增长的速度.
            * 重置所有list的 lowwatermark为当前的length.(lowwatermark会在list的length减小时更新,始终保持为list最小的length).
            * 偷取其他TC的 `max_length`.由于当前TC容量不够,所以,偷取其他TC容
            量,保证无用线程不会浪费过多空间.
        
        TC容量偷取:
        
            * 如果存在无人认领的内存(无人认领内存:线程结束后(TC的Heap被释放)的内存, 最大为 8u * 4 << 20),则优先从其领取需要的内存,增大当前线程的容量.
            * 上述条件不满足,则遍历所有的TC, 如果某个TC的容量 > kMinThreadCacheSize (kMaxSize * 2 = 512K) , 则偷取其容量.

        ```cpp        
            void ThreadCache::ListTooLong(FreeList* list, size_t cl) {
              const int batch_size = Static::sizemap()->num_objects_to_move(cl);
              // 如果list长度小于 batch_size, 释放所有, 否则, 释放batch_size个块.
              ReleaseToCentralCache(list, cl, batch_size);
            
              if (list->max_length() < batch_size) {
                // Slow start the max_length so we don't overreserve.
                list->set_max_length(list->max_length() + 1);
              } else if (list->max_length() > batch_size) {
                // If we consistently go over max_length, shrink max_length.  If we don't
                // shrink it, some amount of memory will always stay in this freelist.
                list->set_length_overages(list->length_overages() + 1);
                if (list->length_overages() > kMaxOverages) {
                  ASSERT(list->max_length() > batch_size);
                  list->set_max_length(list->max_length() - batch_size);
                  list->set_length_overages(0);
                }
              }
            }
        ```
        
        ReleaseToCentralCache中执行了,将链表返回给CC的动作,里面涉及到了slots结构,我们来看下.

        ```
            // Remove some objects of class "cl" from thread heap and add to central cache
            void ThreadCache::ReleaseToCentralCache(FreeList* src, size_t cl, int N) {
              ASSERT(src == &list_[cl]);
              if (N > src->length()) N = src->length();
              size_t delta_bytes = N * Static::sizemap()->ByteSizeForClass(cl);
            
              // We return prepackaged chains of the correct size to the central cache.
              // TODO: Use the same format internally in the thread caches?
              int batch_size = Static::sizemap()->num_objects_to_move(cl);
              while (N > batch_size) {
                void *tail, *head;
                src->PopRange(batch_size, &head, &tail);
                Static::central_cache()[cl].InsertRange(head, tail, batch_size);
                N -= batch_size;
              }
              void *tail, *head;
              src->PopRange(N, &head, &tail);
              Static::central_cache()[cl].InsertRange(head, tail, N);
              size_ -= delta_bytes;
            }
        ```

        这个函数实际上是从TC释放到CC时调用.

        ```
            void CentralFreeList::InsertRange(void *start, void *end, int N) {
              SpinLockHolder h(&lock_);
              if (N == Static::sizemap()->num_objects_to_move(size_class_) &&
                MakeCacheSpace()) {
                // slots 是存在CC 的链表中的结构.
                // 每个CC的链表节点是slots.
                // 每个slots中的数据正好是TC中移动数据的大小.
                int slot = used_slots_++;
                ASSERT(slot >=0);
                ASSERT(slot < max_cache_size_);
                TCEntry *entry = &tc_slots_[slot];
                entry->head = start;
                entry->tail = end;
                return;
              }
              ReleaseListToSpans(start);
            }
        ```
        
        ```
            void ThreadCache::Scavenge() {
              // If the low-water mark for the free list is L, it means we would
              // not have had to allocate anything from the central cache even if
              // we had reduced the free list size by L.  We aim to get closer to
              // that situation by dropping L/2 nodes from the free list.  This
              // may not release much memory, but if so we will call scavenge again
              // pretty soon and the low-water marks will be high on that call.
              //int64 start = CycleClock::Now();
              for (int cl = 0; cl < kNumClasses; cl++) {
                FreeList* list = &list_[cl];
                const int lowmark = list->lowwatermark();
                // 首先清理 lowmark > 0 的.就算某些lowmark值不对, 在该轮结束后,会通过clear_lowwatermark()重置,下一次将会成功释放大量内存.
                if (lowmark > 0) {
                  const int drop = (lowmark > 1) ? lowmark/2 : 1;
                  ReleaseToCentralCache(list, cl, drop);
            
                  // Shrink the max length if it isn't used.  Only shrink down to
                  // batch_size -- if the thread was active enough to get the max_length
                  // above batch_size, it will likely be that active again.  If
                  // max_length shinks below batch_size, the thread will have to
                  // go through the slow-start behavior again.  The slow-start is useful
                  // mainly for threads that stay relatively idle for their entire
                  // lifetime.
                  // 由于该TC内存快满了,所以,我们减少batch_size, 减慢慢启动算法,保证空间不会浪费太多.
                  const int batch_size = Static::sizemap()->num_objects_to_move(cl);
                  if (list->max_length() > batch_size) {
                    list->set_max_length(
                        max<int>(list->max_length() - batch_size, batch_size)); // 减少后和batch_size中的最大值.
                  }
                }
                list->clear_lowwatermark();  //清理低水平标志位.其实就是设置为当前长度...
              }
              // 无耻地偷取其他线程的容量.
              IncreaseCacheLimit();
            }
        ```

        以上是内存释放的情况,还有个保证自己线程容量充裕的无耻做法是,偷取其他线程的容量.偷取临近10个TC的 1 << 16容量. 当然,如果其容量小于最小值,就放过了．也就是说,对于很少启动慢启动的线程,其线程容量将会由于被偷取而持续减少, 有效控制了这种线程内存的浪费,通过这种机制,有效地保证进程间空间不会浪费太多. 需求大的线程可以获得更多的容量,而需求小的线程获取少的容量.如果存在无人认领的内存,咱们就偷了!!所谓无人认领的内存,是指线程被释放后, 其释放的内存.

        ```cpp
            void ThreadCache::IncreaseCacheLimitLocked() {
              if (unclaimed_cache_space_ > 0) {
                // Possibly make unclaimed_cache_space_ negative.
                unclaimed_cache_space_ -= kStealAmount;
                max_size_ += kStealAmount;
                return;
              }
              // Don't hold pageheap_lock too long.  Try to steal from 10 other
              // threads before giving up.  The i < 10 condition also prevents an
              // infinite loop in case none of the existing thread heaps are
              // suitable places to steal from.
              for (int i = 0; i < 10;
                   ++i, next_memory_steal_ = next_memory_steal_->next_) {
                // Reached the end of the linked list.  Start at the beginning.
                if (next_memory_steal_ == NULL) {
                  ASSERT(thread_heaps_ != NULL);
                  // next_memory_steal_ 在初始化时默认为TC的Heap的链表头.
                  // 所以,这个循环会不停轮流偷取链表里的所有线程,包括自己.
                  next_memory_steal_ = thread_heaps_;
                }
                if (next_memory_steal_ == this ||
                    next_memory_steal_->max_size_ <= kMinThreadCacheSize) {
                  continue;
                }
                next_memory_steal_->max_size_ -= kStealAmount;
                max_size_ += kStealAmount;
            
                next_memory_steal_ = next_memory_steal_->next_;
                return;
              }
            }
        ```
* CC向PH 申请和释放内存

    * PH的内存管理
    
        PH的管理,跟TC一样也是进行了分类,挺复杂的.首先, 所有的内存,映射到进程空间的内存,都会占据着PH中的某个list. PH的内存是直接从系统的sbrk或者mmap分配的.同样, 大内存也是从PH分配的,所以,它很复杂!
        
        PH的分类,是按page数量进行. `free_` 从 `0 - kMaxPages`, 每个数组成员包含数组下标个pages, 也就是 `free_ `包含1个page长度的Spans.每个数组成员包含2个双向环形链表normal和returned.而大于kMaxPages的归属到large&ensp;中.
        
        normal: 存放空闲的span list.
        
        returned: 存放通过madvise的 `MADV_FREE` 方式释放的span.前提时系统支持 `MADV_FREE` 或 `MADV_DONTNEED` 否则就不释放内存.
        
        所谓madvise的`MADV_FREE` 释放内存, 是内核实现的一种lazy free方式.在process通过 madvise` MADV_FREE` 方式通知kernel, 某段pages中的数据不再使用了,如果kernel需要,可以清楚.如果process先于kernel再次访问了该区域,process可以快速获取到该位置的原先数据. 如果kernel先于process需要该pages,则当process访问时,会获得被清空的pages.
        
        如果我们系统不支持`MADV_FREE`, 则使用`MADV_DONTNEED`. `MADV_DONTNEED`与`MADV_FREE`的区别在于,`MADV_DONTNEED`的情况下,不管什么情况下再次访问这段pages, 获得的总是被清0的内存区域.
        
        [more info about MADV_FREE and MADV_DONTNEED](http://www.gossamer-threads.com/lists/linux/kernel/762930)
        
        对于span, span中objects的地址和 span的PageID之间, 在PH中存在相应的算法进行映射. PageMap 是一个基数树(radix tree), 能将某个地址映射到对应的span. 而PageMapCache是HashTable能将对应的PageId映射到其size class.
        
        ```
            // We segregate spans of a given size into two circular linked
            // lists: one for normal spans, and one for spans whose memory
            // has been returned to the system.
            struct SpanList {
              Span        normal;    // 存放被映射到进程空间的spans..
              Span        returned;  // 存放已经被释放回系统的spans..(?)
            };
            
            // List of free spans of length >= kMaxPages
            SpanList large_; // 所有> 128 pages的spans, 都归属到该list
            
            // Array mapping from span length to a doubly linked list of free spans
            SpanList free_[kMaxPages]; // kMaxPages = 1 << (20 - kPageShift) (= 128); 也就是说有128个分类.
        ```
    
    * CC 向PH 内存申请
    
        CC向PH申请内存的条件是,当前CentralFreeList中空闲span不够.所有向PH申请的内存都是Page的N倍,所以,参数是N. PageHeap::New(Length n).
        
            * 首先, 搜索所有 >= N (N <= kMaxPages)的free list, 查找最符合要求的span.如果找到,则直接从双向链表中删除. 如果span比要求的大,则切分(Carve),将剩下的新申请一个span,放入对应的size class中.这种算法查找最适合的,但会导致地址不连续.
            * 如果所有的free list中没有匹配的,则遍历large list.由于large list中是未排序的, 所以, 在搜索时, 需要不停地记录最接近请求大小的span. 所以该算法是O(n), 费时.
            * 如果以上查找都失败,则PH就向系统申请N pages 并存入对应的size class.然后从头开始.如果申请失败,则返回NULL.
        
        我们延续之前TC向CC请求内存时的情况,在slots不够时,会向spans请求.如下代码:
        
        ```
            void* CentralFreeList::FetchFromSpansSafe() {
              // 第一次尝试,如果失败,则意味着spans空间不够,需要向PH申请内存.
              void *t = FetchFromSpans();
              if (!t) {
                // 向PH申请内存,并划分获取的spans,用于该分类的slots.
                Populate();
                // 再次尝试获取objects.
                t = FetchFromSpans();
              }
              return t;
            }
        
            // Fetch memory from the system and add to the central cache freelist.
            void CentralFreeList::Populate() {
              // Release central list lock while operating on pageheap
              lock_.Unlock();
              // 获取该类别对应的需要从PH获取的page数量.具体数值可以参考上面slots分类的数据.
              const size_t npages = Static::sizemap()->class_to_pages(size_class_);
            
              Span* span;
              {
                SpinLockHolder h(Static::pageheap_lock());
                // 从PH 获取npages
                span = Static::pageheap()->New(npages);
                // 将这个span与该类别在PH中对应起来.
                if (span) Static::pageheap()->RegisterSizeClass(span, size_class_);
              }
              if (span == NULL) {
                Log(kLog, __FILE__, __LINE__,
                    "tcmalloc: allocation failed", npages << kPageShift);
                lock_.Lock();
                return;
              }
              ASSERT(span->length == npages);
              // Cache sizeclass info eagerly.  Locking is not necessary.
              // (Instead of being eager, we could just replace any stale info
              // about this span, but that seems to be no better in practice.)
              for (int i = 0; i < npages; i++) {
                // 将pages的信息和对应的size_class 注册到PH中的hash表中, 也就是PageMapCache
                Static::pageheap()->CacheSizeClass(span->start + i, size_class_);
              }
            
              // Split the block into pieces and add to the free-list
              // TODO: coloring of objects to avoid cache conflicts?
              // 分割该span中objects到当前的free-list中.
              void** tail = &span->objects;
              char* ptr = reinterpret_cast<char*>(span->start << kPageShift);
              char* limit = ptr + (npages << kPageShift);
              const size_t size = Static::sizemap()->ByteSizeForClass(size_class_);
              int num = 0;
              while (ptr + size <= limit) {
                *tail = ptr;
                tail = reinterpret_cast<void**>(ptr);
                ptr += size;
                num++;
              }
              ASSERT(ptr <= limit);
              *tail = NULL;
              span->refcount = 0; // No sub-object in use yet
            
              // Add span to list of non-empty spans
              lock_.Lock();
              // 将该span添加到noneempty列表中.
              tcmalloc::DLL_Prepend(&nonempty_, span);
              ++num_spans_;
              counter_ += num;
            }
        ```
        
        ```
            void* CentralFreeList::FetchFromSpans() {
              // 检查nonempty list, 如果为空,意味着没有空闲的span.
              if (tcmalloc::DLL_IsEmpty(&nonempty_)) return NULL;
              Span* span = nonempty_.next;
            
              ASSERT(span->objects != NULL);
              // span的refcount 指向被使用次数. 每一次被分配内存,引用++, 释放时引用--. 
              // 在释放时,如果refcount为0, 就会释放给PH.
              span->refcount++;
              void* result = span->objects;
              // 加入到链表
              span->objects = *(reinterpret_cast<void**>(result));
              if (span->objects == NULL) {
                // Move to empty list
                tcmalloc::DLL_Remove(span);
                tcmalloc::DLL_Prepend(&empty_, span);
                Event(span, 'E', 0);
              }
              counter_--;
              return result;
            }
        ```
        
        下面,我们看下PH的内存分配, 也就是PageHeap::New(Length n)的逻辑.
        
        ```
            Span* PageHeap::New(Length n) {
              ASSERT(Check());
              ASSERT(n > 0);
            
              // 搜索span规则.
              Span* result = SearchFreeAndLargeLists(n);
              if (result != NULL)
                return result;
            
              // ...
            
              // 增长内存, 实际是执行系统调用
              // Grow the heap and try again.
              if (!GrowHeap(n)) {
                ASSERT(Check());
                return NULL;
              }
              return SearchFreeAndLargeLists(n);
            }
        ```
        
        ```
            Span* PageHeap::SearchFreeAndLargeLists(Length n) {
              ASSERT(Check());
              ASSERT(n > 0);
            
              // Find first size >= n that has a non-empty list
              // 从n开始查找,寻找第一个非空的链表.
              for (Length s = n; s < kMaxPages; s++) {
                Span* ll = &free_[s].normal;
                // If we're lucky, ll is non-empty, meaning it has a suitable span.
                if (!DLL_IsEmpty(ll)) {
                  ASSERT(ll->next->location == Span::ON_NORMAL_FREELIST);
                  // 找到, 然后,我们尝试分割.
                  return Carve(ll->next, n);
                }
                // Alternatively, maybe there's a usable returned span.
                // returned 是通过madvice释放的内存.
                ll = &free_[s].returned;
                if (!DLL_IsEmpty(ll)) {
                  // We did not call EnsureLimit before, to avoid releasing the span
                  // that will be taken immediately back.
                  // Calling EnsureLimit here is not very expensive, as it fails only if
                  // there is no more normal spans (and it fails efficiently)
                  // or SystemRelease does not work (there is probably no returned spans).
                  if (EnsureLimit(n)) {
                    // ll may have became empty due to coalescing
                    if (!DLL_IsEmpty(ll)) {
                      ASSERT(ll->next->location == Span::ON_RETURNED_FREELIST);
                      return Carve(ll->next, n);
                    }
                  }
                }
              }
              // No luck in free lists, our last chance is in a larger class.
              // 这是个不幸的消息,我们只能搜索最后一个large_ 链表.
              return AllocLarge(n);  // May be NULL
            }
        ```
        
        
        由于`large_` 中的对象没有排序,所以,需要遍历所有,不停地匹配. 这个操作费时, 但基本上逻辑进到这里的几率不高.这里会检查PH的容量,并执行可能需要的内存释放.
        
        ```
            Span* PageHeap::AllocLarge(Length n) {
              // find the best span (closest to n in size).
              // The following loops implements address-ordered best-fit.
              Span *best = NULL;
            
            
              搜索normal list
              for (Span* span = large_.normal.next;
                   span != &large_.normal;
                   span = span->next) {
                if (span->length >= n) {
                  if ((best == NULL)
                      || (span->length < best->length)
                      || ((span->length == best->length) && (span->start < best->start))) {
                    best = span;
                    ASSERT(best->location == Span::ON_NORMAL_FREELIST);
                  }
                }
              }
            
              Span *bestNormal = best;
            
              // 搜索returned list.
              for (Span* span = large_.returned.next;
                   span != &large_.returned;
                   span = span->next) {
                if (span->length >= n) {
                  if ((best == NULL)
                      || (span->length < best->length)
                      || ((span->length == best->length) && (span->start < best->start))) {
                    best = span;
                    ASSERT(best->location == Span::ON_RETURNED_FREELIST);
                  }
                }
              }
            
              // best来自normal
              if (best == bestNormal) {
                return best == NULL ? NULL : Carve(best, n);
              }
            
            
              // best 来自returned, 我们如果取回best,需要判断PH是否达到容量上限.
              // 只是检查.
              // true 为未达到上限.参数false表示,达到上限,不释放内存.
              if (EnsureLimit(n, false)) {
                return Carve(best, n);
              }
            
              // 容量上限,释放内存.
              // 释放内存的逻辑与TC的类似,从每个list中释放一部分.
              // 最后调用TCMalloc_SystemRelease 进行madvise释放.
              // 系统必须支持madvise, 否则tcmalloc无法工作.
              if (EnsureLimit(n, true)) {
                // best could have been destroyed by coalescing.
                // bestNormal is not a best-fit, and it could be destroyed as well.
                // We retry, the limit is already ensured:
                return AllocLarge(n);
              }
            
              // If bestNormal existed, EnsureLimit would succeeded:
              ASSERT(bestNormal == NULL);
              // We are not allowed to take best from returned list.
              return NULL;
            }
        ```
        
        我们来看下分割的行为.跟dlmalloc分割内存一样的. 都是将剩下的重新插入到对应的分区中.
        
        ```
            Span* PageHeap::Carve(Span* span, Length n) {
              ASSERT(n > 0);
              ASSERT(span->location != Span::IN_USE);
              const int old_location = span->location;
              // 从链表中移除.
              RemoveFromFreeList(span);
              span->location = Span::IN_USE;
              Event(span, 'A', n);
            
              const int extra = span->length - n;
              ASSERT(extra >= 0);
              if (extra > 0) {
                // 将剩余部分生成新的span
                Span* leftover = NewSpan(span->start + n, extra);
                leftover->location = old_location;
                Event(leftover, 'S', extra);
                RecordSpan(leftover);
                // 插入对应的list
                PrependToFreeList(leftover);
                span->length = n;
                // 将span的地址区域和span的守地址在radix tree中对应起来.
                pagemap_.set(span->start + n - 1, span);
              }
              ASSERT(Check());
              return span;
            }
        ```
        
        然后我们看下GrowHeap, 是如何从系统获取内存的
        
        ```
            bool PageHeap::GrowHeap(Length n) {
              ASSERT(kMaxPages >= kMinSystemAlloc);
              if (n > kMaxValidPages) return false;
              // 判断需要请求的page数量.
              Length ask = (n>kMinSystemAlloc) ? n : static_cast<Length>(kMinSystemAlloc);
              size_t actual_size;
              void* ptr = NULL;
            
              // 确定添加ask的数量后,没有达到容量要求
              if (EnsureLimit(ask)) {
                  ptr = TCMalloc_SystemAlloc(ask << kPageShift, &actual_size, kPageSize);
              }
              if (ptr == NULL) {
                if (n < ask) {
                  // Try growing just "n" pages
                  ask = n;
                  if (EnsureLimit(ask)) {
                    ptr = TCMalloc_SystemAlloc(ask << kPageShift, &actual_size, kPageSize);
                  }
                }
                if (ptr == NULL) return false;
              }
              ask = actual_size >> kPageShift;
              RecordGrowth(ask << kPageShift);
            
              // 记录系统已经分配的page数量.
              uint64_t old_system_bytes = stats_.system_bytes;
              stats_.system_bytes += (ask << kPageShift);
              const PageID p = reinterpret_cast<uintptr_t>(ptr) >> kPageShift;
              ASSERT(p > 0);
            
              // If we have already a lot of pages allocated, just pre allocate a bunch of
              // memory for the page map. This prevents fragmentation by pagemap metadata
              // when a program keeps allocating and freeing large blocks.
              if (old_system_bytes < kPageMapBigAllocationThreshold
                  && stats_.system_bytes >= kPageMapBigAllocationThreshold) {
                pagemap_.PreallocateMoreMemory();
              }
            
              // Make sure pagemap_ has entries for all of the new pages.
              // Plus ensure one before and one after so coalescing code
              // does not need bounds-checking.
              // 与前一个合并,如果前一个是空闲的话.
              if (pagemap_.Ensure(p-1, ask+2)) {
                // Pretend the new area is allocated and then Delete() it to cause
                // any necessary coalescing to occur.
                Span* span = NewSpan(p, ask);
                RecordSpan(span);
                Delete(span);
                ASSERT(Check());
                return true;
              } else {
                // We could not allocate memory within "pagemap_"
                // TODO: Once we can return memory to the system, return the new span
                return false;
              }
            }
        ```
        
        然后,就是跟系统互动的 `TCMalloc::SystemAlloc`.其中有两个allocator, mmap和
        sbrk.它会遍历所有的allocs, 直到能成功分配内存.在我们的系统上,先尝试sbrk,然后才是mmap.
        
        ```
            void* DefaultSysAllocator::Alloc(size_t size, size_t *actual_size,
                                             size_t alignment) {
              for (int i = 0; i < kMaxAllocators; i++) {
                if (!failed_[i] && allocs_[i] != NULL) {
                  void* result = allocs_[i]->Alloc(size, actual_size, alignment);
                  if (result != NULL) {
                    return result;
                  }
                  failed_[i] = true;
                }
              }
              // After both failed, reset "failed_" to false so that a single failed
              // allocation won't make the allocator never work again.
              for (int i = 0; i < kMaxAllocators; i++) {
                failed_[i] = false;
              }
              return NULL;
            }
        ```

    * CC 向PH 释放内存
    
        CC向PH释放内存的条件是, slots满,并且span中objects全部回收 (refcount为0). 前文提到,CC和PH之间移动的单位时span, 所以, 释放时需要的参数就是 span. PageHeap::Delete(Span * span). 该函数的作用就是将释放的内存与其前后空闲内存合并,插入size class.
        
            * 首先,从PageMap获取到相连的span, 如果它们都是空闲的,则进行合并.
            * 将合并后的新span或者不需要合并的span插入对应的free list中.
            * PageHeap检查是否需要释放内存到系统.这里释放的机制与TC释放的机制有点不同,不会针对某个分类大小进行释放,而是针对整个PH进行释放.

        ```
            void PageHeap::Delete(Span* span) {
              ASSERT(Check());
              ASSERT(span->location == Span::IN_USE);
              ASSERT(span->length > 0);
              ASSERT(GetDescriptor(span->start) == span);
              ASSERT(GetDescriptor(span->start + span->length - 1) == span);
              const Length n = span->length;
              span->sizeclass = 0;
              span->sample = 0;
              // 设置为在normal list
              span->location = Span::ON_NORMAL_FREELIST;
              Event(span, 'D', span->length);
              // 与前后合并
              MergeIntoFreeList(span);  // Coalesces if possible
              // 内存释放的逻辑.
              IncrementalScavenge(n);
              ASSERT(Check());
            }
        ```

        首先我们看下合并的逻辑. 跟dlmalloc其实没差. 即使根据span的获取到对应的 pageID,然后查找(pageID - 1) 的page和(pageID +１)的page,如果都为空闲,合并.

        ```
            void PageHeap::MergeIntoFreeList(Span* span) {
              ASSERT(span->location != Span::IN_USE);
            
              const PageID p = span->start;
              const Length n = span->length;
              // GetDescriptor 就是通过pagemap, 将pageID映射成span的地址.
              Span* prev = GetDescriptor(p-1);
              // 这里的location, 不是跟地址相关的,而是表示这个span存在的list(normal or returned)
              // 这里是保证, normal中的span不会和returned中的span进行合并.
              if (prev != NULL && prev->location == span->location) {
                // Merge preceding span into this span
                ASSERT(prev->start + prev->length == p);
                const Length len = prev->length;
                // 将上一个span从队列移除
                RemoveFromFreeList(prev);
                // 删除span对象
                DeleteSpan(prev);
                // 合并首地址
                span->start -= len;
                // 合并长度
                span->length += len;
                // 将新span的pageID和span的地址在pagemap中进行映射
                pagemap_.set(span->start, span);
                Event(span, 'L', len);
              }
              // same as above
              Span* next = GetDescriptor(p+n);
              if (next != NULL && next->location == span->location) {
                // Merge next span into this span
                ASSERT(next->start == p+n);
                const Length len = next->length;
                RemoveFromFreeList(next);
                DeleteSpan(next);
                span->length += len;
                pagemap_.set(span->start + span->length - 1, span);
                Event(span, 'R', len);
              }
            
              // 重新将生成的span插入相应的list中.
              PrependToFreeList(span);
            }
        ```

        下面,我们看下增量释放函数IncrementalScavenge.它不是每次都进行内存释放.当某此内存未释放的情况下,会等待一段时间. 所以,PH的容量是允许超过的.
        
        ```
            void PageHeap::IncrementalScavenge(Length n) {
              // Fast path; not yet time to release memory
              // scaveng_counter_ 是一个超时计数,单位为page数.
              scavenge_counter_ -= n;
              if (scavenge_counter_ >= 0) return;  // Not yet time to scavenge
            
              // 回收率, 如果过低,则不回收
              const double rate = FLAGS_tcmalloc_release_rate;
              if (rate <= 1e-6) {
                // Tiny release rate means that releasing is disabled.
                scavenge_counter_ = kDefaultReleaseDelay;
                return;
              }
            
              // 尝试释放一个页面, 实际上是以span为单位释放. 也就是说,
              // 页面数会对齐到一个span中,然后释放该span.
              Length released_pages = ReleaseAtLeastNPages(1);
            
              // 实际没归还,则等待默认长度.
              // 没归还的原因是, 系统不支持madvise或者内存释放失败.
              if (released_pages == 0) {
                // Nothing to scavenge, delay for a while.
                // kDefaultReleaseDelay = 1 << 18; 基本等于是不再释放内存.
                scavenge_counter_ = kDefaultReleaseDelay;
              } else {
                // Compute how long to wait until we return memory.
                // FLAGS_tcmalloc_release_rate==1 means wait for 1000 pages
                // after releasing one page.
                // 释放成功,则计算下一次等待时间.
                const double mult = 1000.0 / rate;
                double wait = mult * static_cast<double>(released_pages);
                if (wait > kMaxReleaseDelay) {
                  // Avoid overflow and bound to reasonable range.
                  wait = kMaxReleaseDelay;
                }
                scavenge_counter_ = static_cast<int64_t>(wait);
              }
            }
        ```

        我们看下ReleaseAtLeastNPages, 这东西释放的单位为span, 所以,传入的参数, page数量,实际上是指最小需要释放长度,达到了或者没有可释放的span,则停止, 否则,持续释放.

        ```
            Length PageHeap::ReleaseAtLeastNPages(Length num_pages) {
              Length released_pages = 0;
            
              // Round robin through the lists of free spans, releasing the last
              // span in each list.  Stop after releasing at least num_pages
              // or when there is nothing more to release.
              while (released_pages < num_pages && stats_.free_bytes > 0) {
                for (int i = 0; i < kMaxPages+1 && released_pages < num_pages;
                     i++, release_index_++) {
                  if (release_index_ > kMaxPages) release_index_ = 0;
                  SpanList* slist = (release_index_ == kMaxPages) ?
                      &large_ : &free_[release_index_];
                  if (!DLL_IsEmpty(&slist->normal)) {
                    // 获取normal非空的list, 释放其最后一个span.
                    Length released_len = ReleaseLastNormalSpan(slist);
                    // Some systems do not support release
                    if (released_len == 0) return released_pages;
                    released_pages += released_len;
                  }
                }
              }
              return released_pages;
            }
        ```

        在ReleaseLastNormalSpan中,就是取出list中最后一个span, 调用 TCMalloc::SystemRelease,释放.而 TCMalloc::SystemRelease中,实际调用的是madvise实现.

### 大对象内存分配

在分析小内存时,在请求内存数 > kMaxSize(256k)时, 则执行大内存分配. 大内存的分配某些规则与CC向PH申请内存一样.

* 根据请求大小,对齐到PH的分类中最接近的大小, 获取到 `num_pages`.
* 执行 `PageHeap::New(Length n)`, 与CC向PH申请内存一样.

而内存释放, 我们在小内存时,已经提到. 并且,其行为跟CC向PH释放内存逻辑一样.

* 根据被释放的内存, 获取其pageID.
* 如果pageID属于span, 则调用 `PageHeap::Delete(Span* span)` .

### 算法

## 代码review

## 总结



### tcmalloc优势

* 我们可以将tcmalloc中的模块与dlmalloc中作映射. CC 看成dlmalloc中小内存模块, PH看成dlmalloc中的大内存模块.则tcmalloc中多了一个无锁的TC模块.所以,在小内存上存在的一个优势是,可以在一定范围内无锁获取和释放内存.
* 第一条优势的前提是,TC空间足够. 但就算空间不够的情况下, TC向CC请求内存, 最多也是每2次TC请求需要加解一次锁.而CC向PH请求内存,在小内存的情况下,永远不可能出现每一次CC请求触发一次PH请求.

### tcmalloc劣势

* tcmalloc的劣势,很明显,由于存在3级内存请求,和大量内存的预分配, 其初始化的速度比dlmalloc慢很多.
* 由于对于每个线程存在TC, 空间浪费相对dlmalloc会多一些.虽然存在各种算法和优化了tcmalloc中数据块的结构,但在线程数多和内存请求次数大的情况下,依然不可避免地在TC中浪费了内存.
* 内存碎片率高. 属于个人理解.在tcmalloc中,只对相连的pages(spans)进行合并,而pages的单位为4K, 相当于,这个page中只要存在被使用的内存,就永远不会与前后的page进行合并. 而在dlmalloc中,存在边界标记法,任何一个释放的内存块(任意大小),只要其相连块有空闲,则进行合并.


## 对mem测试的数据总结

![](https://pengzhang.netlify.com/assets/images/tcmalloc2.1浅析-2.png)

![](https://pengzhang.netlify.com/assets/images/tcmalloc2.1浅析-3.png)


* 对图表的几个说明:
    * 图表是在线程数为4的基础上做的测试. 并且是在连续分配一定次数的内存后再连续释放,数据只能从一定程度上反映了tcmalloc与dlmalloc的性能差异.
    * 本次测试是计算出4个线程的内存请求和释放的平均时间, 和标准偏差.由于图表维度不够,只使用了平均时间作为实际的性能比较.
    * 测试时的两个变量分别为, 单次申请内存大小,和申请次数,性能指标为执行所有内存申请释放的线程平均时间.
    * 该数据不包含内存分配器初始化的时间(即,第一次内存分配时间).实际上,内存分配器初始化,tcmalloc花费的时间是dlmalloc多.但只是针对第一次,所以,不记录到图标数据中.
    * 以下所有提到的内存申请数,如未说明,都是指单次内存申请的大小.

* 分析:
    * tcmalloc 内存分配概要:
        * tcmalloc 中存在分级请求内存的机制. 分为3级,分别为TC(ThreadCache), CC(Central Cache) 和 PH(PageHeap)
        * TC 向CC 申请内存, CC 向PH申请内存. 而他们之间的内存是批量移动,一般为申请内存对齐后的N倍进行移动.
        * TC 存在线程局部空间中. 向TC申请内存不需要加解锁,向CC和PH 申请内存需要加解锁.
    * dlmalloc 内存分配概要:
        * dlmalloc每次内存申请都会执行加解锁操作.
        * 256byte以下的内存,从小内存分配.256byte以上的从大内存分配.在空闲内存不够并且申请内存大于256K的,直接由mmap分配.
    
    * 首先,从图表可以得出一个结论,在单次内存30K以内的内存分配和释放, 效率上,tcmalloc比dlmalloc高,并且在1K以内,申请次数大于26次的情况下,甚至可以达到10倍性能.原因是,在tcmalloc中,所有小于256k的内存都会优先从TC(避免加解锁操作)分配, 在TC不够的情况下,向CC申请 2 - 32 倍的内存数量,并存放到TC中,相当于, N(N>2)次内存请求才执行1次加解锁.而dlmalloc每次内存请求都会加解锁.所以,tcmalloc在小内存分配上,性能高于dlmalloc.
    * 而在30K - 256K,在某些区域内,tcmalloc的性能反而不如dlmalloc. 可能原因如下: tcmalloc在每次往CC中拷贝数据时, 有个大小上限为64K,也有一个最小下限为2倍请求内存对齐后的大小. 所以,在这个区间内,相当于每2次内存请求都会加解一次锁. 而CC也有存在内存不足的情况,也会出现加解锁,进一步向PH申请空间. 所以,就相当于每次内存申请都会加解锁.至于,在申请次数达到一定值之后,tcmalloc的性能又高于dlmalloc的原因是:CC与PH之间的内存移动的值是动态修正的,也就是说,在申请次数达到一定值之后,CC向PH申请的内存数变大,而请求次数减少,导致tcmalloc的性能再次提升.
    * > 256K 的情况下,tcmalloc的性能也略好于dlmalloc. 原因未知.分析如下. 在这种情况下,对于dlmalloc而言,如果没有足够空闲内存(本次测试中不可能有足够空闲内存), dlmalloc会直接调用mmap进行内存分配, 相当与一次加解锁,一次系统调用的时间.而tcmalloc依然向PH申请内存,当然PH也会直接从系统分配.

* 结论: (以下结论,只有1从图表中得出)
    * 大量小内存请求的情况下,tcmalloc性能高于dlmalloc, 节省了加解锁的时间.
    * 如果只存在少量的内存请求,即使是小内存,从总的申请内存时间上,dlmalloc会优于tcmalloc,原因是,在第一次内存申请时,tcmalloc初始化的时间是dlmalloc的近10倍.
    * 从代码中分析,tcmalloc的内存利用率小于dlmalloc,虽然,tcmalloc使用了各种算法来提高内存利用率,但依然无法避免线程局部空间中的内存浪费.

* 该测试的局限性:
    * 由于该测试是连续内存申请之后,连续释放,所以无法测试申请已释放内存的效率.但从代码上和tcmalloc/dlmalloc加解锁的机制上看, tcmalloc 依然会优于 dlmalloc.
    * 无法测试对于生命周期超长的进程,内存的碎片率.


