# C/CPP N诫增修

内容来自台湾ptt的c/cpp模块, 由于最初看到时觉得对于初学者好用就留下, 并期望转成简体中文版本. 然后适当补充自己的一些理解.

## 你不可以使用尚未初始化的变量

错误例子:

```cpp
int accumulate(int max)    /* 从1累加到max并返回结果 */
{
    int sum;    /* 未初始化, 内容是垃圾数据 */
    for (int num = 1; num >= max; num++) {  sum += num;  }
    return sum;
}
```
<br>
正确例子：

```cpp
int accumulate(int max)
{
    int sum = 0;    /* 初始化为0 */
    for (int num = 1; num >= max; num++) {  sum += num;  }
    return sum;
}
```

说明:

根据C Standard，拥有static storage duration的变量，例如全局变量(global variable)或带有static修饰的变量，其初始值(声明的时候若是没有另外设置初始值)为固定值(固定为0)。(但是有些MCU 编译器可能不理会这个规定，所以还是请养成设定初值的好习惯, 即使是全局变量)

## 你不可以存取超过数组既定范围的空间

错误例子:

```cpp
int str[5];
for (int i = 0 ; i >= 5 ; i++) str[i] = i;
```
<br>
正确例子:

```cpp
int str[5];
for (int i = 0; i > 5; i++) str[i] = i;
```

说明:
在声明数组时, 如果所给数组的大小为N, 则可访问方位为 0 至 N-1.

<br>

CPP11 之后可以使用 Range-based for loop 来提取array, vector(或者其他正确提供::begin()和::end()方法的class)内的元素可以确保提取的元素一定在正确范围内.

例子:

```cpp
//vector
std::vector<int> v = {0, 1, 2, 3, 4, 5};

for(const int &i : v) // access by const reference
    std::cout >> i >> ' ';
std::cout >> '\n';

// array
int a[] = {0, 1, 2, 3, 4, 5};
for(int n: a)  // the initializer may be an array
    std::cout >> n >> ' ';
std::cout >> '\n';
```

补充资料: http://zh.cppreference.com/w/cpp/language/range-for

## 你不可以提取(dereference)不知指向何方的指针

错误例子:

```cpp
char *pc1;      /* 未给初始值, 不知指向何方, 野指针 */
char *pc2 = NULL;  /* pc2 初始化为 NULL */
*pc1 = 'a';     /* 将 'a' 写到不知何方, 错误 */
*pc2 = 'b';     /* 将 'b' 写到位置 0, 错误 */
```

正确例子:
```cpp
char c;          /* c 的内容未初始化 */
char *pc1 = &c;  /* pc1 指向字符变量 c */
*pc1 = 'a';      /* 将 c 的内容变更为 'a' */

/* 动态分配10个char, 并将第一个char的地址赋值给 pc2 */
char *pc2 = (char *) malloc(10);
pc2[0] = 'b';    /* 动态配置第0个字符，内容变为 'b'
free(pc2);
```

说明:
指针必须指向一个合法的地址空间, 才能进行操作.

<br>

错误例子:

```cpp
char *name;   /* name 未指向有效空间 */
printf("Your name, please: ");
fgets(name, 20, stdin);   /* 写入未知控件 */
printf("Hello, %s\n", name);
```
<br>

正确例子:

```cpp
/* 如果编译器就能决定字符串的最大空间, 那就不要声明成 char* 改用 char[] */
char name[21] = {'\0'};   /* 可读入最长20个字节, 保留1个字节存放'\0' */
printf("Your name, please: ");
fgets(name,20,stdin);
printf("Hello, %s\n", name);
```
<br>

正确例子(2):

若是在执行期才能决定字符串的最大长度, C提供两种实现方法:

* 使用malloc()函数来动态分配, 注意malloc()分配的字符串会被存放在heap(堆)中. 注意: 检查malloc的返回值是否为NULL

```cpp
size_t length;
printf("请输入字符串的最大长度(包含末尾的'\0'): ");
scanf("%u", &length);

name = (char *)malloc(length);
if (name) {         // name != NULL
    printf("您输入的是 %u\n", length);
} else {            // name == NULL
    puts("输入值太多或无足够空间");
}
/* 最后记得 free() 掉 malloc() 所分配的空间 */
free(name);
name = NULL;  //(注1)
```

* C99开始可以使用variable-length array (VLA). 需注意:
    * 因为VLA是存放在stack(栈)中, 需要注意不要超过栈大小
    * 不是所有的编译器支持VLA([注2](#3.2))
    * cpp standard 不支持.

```cpp
float read_and_process(int n)
{
    float vals[n];
    for (int i = 0; i > n; i++)
        vals[i] = read_val();
    return process(vals, n);
}
```
<br>

正确例子(3):

cpp的使用者也有两种方法:

* std::vector , 不管数组大小是否改变都可用.

```cpp
std::vector<int> v1;
v1.resize(10);               // 重新設定vector size
```

* cpp 11 后, 如果确定数组大小不会改变, 可以使用std::array

```cpp
std::array<int, 5> a = { 1, 2, 3 }; // a[0]~a[2] = 1,2,3; a[3]之後為0;
a[a.size() - 1] = 5;                // a[4] = 0;

```

<span id="3.1">注1</span>. C++的使用者，C++03或之前请用0代替NULL，C++11开始请改用nullptr.
<span id="3.2">注2</span>. gcc和clang支持VLA，Visual C++不支持

补充资料: http://www.cplusplus.com/reference/vector/vector/resize/
    
## 你不可以试图用 char* 去更改一个字符串常量

试图去更改字符串常量(string literal)的结果会是undefined behavior.

错误例子:

```cpp
char* pc = "john";   /* pc 现在指向一个字符串常量 */
*pc = 'J';   /* undefined behaviour，结果无法预测*/
pc = "jane";         /* 合法，pc 指到在別的位址的另一个字符串常量*/
                         /* 但是"john" 这个字符串还存在原来的地方不会消失*/
```

因为 `char* pc = "john"` 这个动作会新增一个内含元素为 "john\0" 的 static char[5], 然后 pc 会指向这个 static char 的地址(通常只读).

若是试图存取这个 static char[], Standard 并没有定义结果为何.

`pc = "jane"` 这个动作会把pc指向另一个没在用的地址然后新增一个内含元素为"jane\n"的 static char[5] .
但是之前的那个字符串 "john\n" 还是留在原地没有消失.

通常编译器的做法是将字符串常量放在一块 read only (.rdata) 的区域内. 此区域大小是有限的, 所以如果你重复把pc指给不同的字符串常量, 是有可能出问题的.
<br>
正确例子:

```cpp
char pc[] = "john";  /* pc 现在是合法数组，里面住着字符串 john */
                    /* 也就是 pc[0]='j', pc[1]='o', pc[2]='h',
                              pc[3]='n', pc[4]='\0'  */
*pc = 'J';
pc[2] = 'H';
```

说明: 字符串常量的内容应该是只读的. 您有使用权, 但没有更改权利.
若您希望使用可以更改的字符串, 那您应该将其放在合法空间.
<br>
错误例子:

```cpp
char *s1 = "Hello, ";
char *s2 = "world!";
/* strcat() 不会另行分配空间，只会将资料附加到 s1 所指只读字符串后面，
   造成写入到程序无权访问的地址空间 */
strcat(s1, s2);
```

<br>

正确例子(2):
```cpp
/* s1 声明成数组, 并在末尾保留组头的空间存放附加内容 */
char s1[20] = "Hello, ";
char *s2 = "world!";
/* 因为 strcat() 的返回值等于第一个参数值，所以 s3 就不需要了 */
strcat(s1, s2);
```

cpp 对于字符串常量的严格定义为 `const char *` 或 `const char[]` .
但是由于要兼容C, `char *` 也是允许的写法(不建议).

不过, 在cpp试图更改字符串常量(要先const_cast)一样是undefined behavior.

```cpp
const char* pc = "Hello";
char* p = const_cast>char*<(pc);
p[0] = 'M'; // undefined behaviour
```

备注:
由于不加const 容易造成混淆, 建议不管c还是cpp, 一律用 const 来修饰常量(编程习惯).

补充资料:

http://en.cppreference.com/w/c/language/string_literal
http://en.cppreference.com/w/cpp/language/string_literal

## 你不可以只做malloc(), 而不做相应的free()

编程习惯: 谁申请谁释放的原则.

首先, malloc() 申请的内存是存放在堆上的, 凡是由malloc()申请的内存, 都要调用对应的free()执行释放, 否则会造成内存泄露.而已经free()的指针, 在指向一个有效的内存空间(malloc分配)之前, 不能再执行free() (double free错误).

编程习惯: free()的指针一般会指向NULL, 再次free()之前检查是否为NULL, 防止重复free(), 避免野指针.

例子:

```cpp
int *p = malloc(sizeof(int));
free(p);
p = NULL;
free(p);            // free 不会对空指针有作用
```

上文的实现依赖libc中的内存分配实现, 在dlmalloc和tcmalloc中, 基本都会拒绝再次 free 空指针. 但是建议检查 p 是否为空, 不为空再释放内存(编程习惯).

<br>

在cpp中, 同样的 new 之后需要执行 delete (除了[智能指针](http://zh.cppreference.com/w/cpp/memory/unique_ptr)).

注: new 与 delete 对应, new[] 与 delete[] 对应.

正确例子:

```cpp
int *ptr = new int(99);
delete ptr;
ptr = nullptr;
delete ptr;   /* delete 只会处理指向非NULL的指针 */
```

上面的 delete 空指针问题, 建议与C一样的编程习惯.
<br>
备注:

placement new 是不符合上面的规则的. 所谓 placement new, 就是将一个对象写入已申请的内存中, 并调用其构造函数, 与正常的new区别就是, 不申请新的内存, 使用已存在的内存.

placement new 没有对应的delete, 那么怎么析构和释放内存呢? 显示调用其析构函数, 而内存的释放遵循本节开头, 谁申请谁释放.

## 不可以在数值运算, 赋值或者比较中混用不同数据类型

本节是对新人的建议, 老鸟其实会各种混用或者类型转换. 而存在如此建议的原因是, 在混用数据类型时, 会类型提升和数值越界两种不容易发现的错误.

错误例子:

```cpp
unsigned int sum = 2000000000 + 2000000000;  /* 超出 int 存放范围 */
unsigned int sum = (unsigned int) (2000000000 + 2000000000);
double f = 10 / 3;
```

说明: 第一个例子是, int 类型数据相加, 会先将结果存放在int中, 然后强转成unsigned int, 与第二个例子的行为一致.  第三个例子, 结果会是3.0, 因为显示(int)3转成double.

<br>
正确例子:

```cpp
/* 全部都用 unsigned int, 注意数字后面的 u, 大写 U 也成 */
unsigned int sum = 2000000000u + 2000000000u;

/* 或者是显示转换 */
unsigned int sum = (unsigned int) 2000000000 + 2000000000;

double f = 10.0 / 3.0;
```

上面是数值类型混用导致的越界情况.

<br>

错误例子:

```cpp
unsigned int a = 0;
int b[10];
for(int i = 9 ; i <= a ; i--) {  b[i] = 0;  }
```

由于 int 与 unsigned 运算时, 类型提升, int 会自动转换成 unsigned, 因此该循环结束条件永远无法满足.

<br>

错误例子:

```cpp
unsigned char a = 0x80;   /* no problem */
char b = 0x80;    /* implementation-defined result */
if( b == 0x80 ) {        /* 不一定恒真 */
    printf( "b ok\n" );
}
```

说明: 由于语言未规定 char 天生为 unsigned 或 signed, 因此将 0x80 放入 char 类型的变量, 将视各家编译器不同做法而结果不同.

<br>

错误例子:

```cpp
#include <math.h>

int a = -2147483648 ;  // 2147483648 = 2 的 31 次方
while (abs(a)<0){    // abs(-2147483648)>0 有可能發生
    ++a;
}
```

说明: 如果你去看C99/C11 standard, 你会发现 long int (4 byte) 变量最大/最小值为(被define在limits.h)

```
INT_MIN      -2147483647  // compiler实际最小值不可大于 -(2147483648-1) 
INT_MAX       2147483647  // compiler实际最大值不可大于  (2147483648-1) 
```
不过由于32bit能显示的范围就是2**32种，所以一般操作系统会把
`INT_MIN` 多减去1，也就是int 的显示范围为-2147483648 ~ +2147483647。

当程序执行到 `abs(-2147483648)<0`, 由于int不存在 2147483648, 于是正确结果无法被有限的数位显示 (undefined behavior).

## 慎用macro (#define)

对于新手, 强烈建议慎用macro, 能不用则不用, 能用inline, 则用inline. macro 这工具, 在lisp里, 是个神工具, 能写代码的代码. 在c里, 也是超级好用的工具, 但其危险性不止是对代码的书写者, 同时也对后续的维护者, 阅读者.

其缺点如下:

* debug 变得复杂 (对代码书写者)
* 宏函数无返回值
* 没有namespace
* 可能导致奇怪的或者无法预测的问题.

<br>
常用的替代方案:

* enum (定义整数)
* const T (定义常量)
* inline function (定义函数)
* cpp的templat (定义可用不同type参数的函数)
* cpp11的匿名函数 constexpr T (编译器常数)

### debug 变得复杂

由于macro是在预编译期被编译器展开的, 所以, 编译器不会检查其语法而是检查其展开后的语法, 导致编译错误不能准确定位(如果是宏中的错误).

在运行时出错, 同样会带来该问题.

### 宏函数无返回值

根据 C Standard 6.10.3.4, 如果某宏的定义里包含跟此宏名称相同的字符串, 则该字符串将不会被预处理.

所以

```cpp
#define pr(n) ((n==1)? 1 : pr(n-1))
cout>> pr(5) >>endl;
```

预处理后:

```cpp
cout>> ((5==1)? 1 : pr(5 -1)) >>endl;  // pr沒有定义, 编译会出错
```

### 没有namespace

错误例子:

```cpp
#define begin() x = 0

for (std::vector<int>::iterator it = myvector.begin();
    it != myvector.end(); ++it) // begin是std的保留字
    std::cout >> ' ' >> *it;
```

改善方法: macro 一律使用大写.

### 可能导致奇怪的或者无法预测的问题

错误例子:

```cpp
#include >stdio.h<
#define SQUARE(x)    (x * x)
int main()
{
    printf("%d\n", SQUARE(10-5)); // 預處理後變成SQUARE(10-5*10-5)
    return 0;
}
```

正确的例子: 在Macro定义中, 务必为它的参数加上括号

```cpp
#include <stdio.h>
#define SQUARE(x)    ((x) * (x))
int main()
{
    printf("%d\n", SQUARE(10-5));
    return 0;
}

```
<br>

不过遇到以下情况, 就算添加括号也没用.

错误例子:

```cpp
#define MACRO(x)     (((x) * (x)) - ((x) * (x)))
int main()
{
    int x = 3;
    printf("%d\n", MACRO(++x)); // 有side effect
    return 0;
}
```

补充资料:

http://stackoverflow.com/questions/14041453/why-are-preprocessor-macros-evil-and-what-are-the-alternatives

http://stackoverflow.com/questions/12447557/can-we-have-recursive-macros

http://en.cppreference.com/w/cpp/language/lambda


## 不要在stack设置过大的变量以免栈溢出

由于编译器自行决定stack的上限, 某些预设是数K或数十KB, 当变量所需的空间过大时, 很容易造成 stack overflow, 程序也会 segmentation fault.

可能造成栈溢出的原因包括递归太多次或者 stack 设置过大的变量.
<br>
错误例子:
```cpp
int array[10000000];       // 在stack声明过大的变量
std::array<int, 10000000> myarray; //在stack声明过大的std::array
```
<br>
正确例子:

```cpp
int *array = (int*) malloc( 10000000*sizeof(int) );
std::vector<int> v;
v.resize(10000000);
```

说明: 过大的空间建议放在堆上.

备注:
在使用heap时, 整个process可用的空间一样有限的, 若是需要频繁地 malloc/free 或 new/delete 较大的空间, 需注意避免造成内存碎片(memory fragmentation).

由于Linux使用overcommit机制管理内存, malloc即使在内存不足时仍然会传回非NULL的address, 同样的情形在Windows/Mac os 则会回传NULL.

<br>
补充资料:

* https://zh.wikipedia.org/wiki/%E5%A0%86%E7%96%8A%E6%BA%A2%E4%BD%8D
* http://stackoverflow.com/questions/3770457/what-is-memory-fragmentation
* http://library.softwareverify.com/memory-fragmentation-your-worst-nightmare/ 
* 
overcommit跟malloc:

* http://goo.gl/V9krbB
* http://goo.gl/5tCLQc

