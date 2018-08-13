# Recovery5.0详解



history:

* version 1.0 by werther zhang @2017-02-06
* version 1.1 by werther zhang @2017-08-07



来源： https://wertherzhang.com

转载请注明来源



本文涉及内容均为作者本人开发，始于2014年， 终于2017年， 盗用资源图片将追究责任！！

本文分享的目的是为所有程序猿们提供思路， 也希望未来在开发的路上，能够得到更多程序猿们分享的好的想法。



## <font color="blue"> recovery简介 </font> ##

Android Recovery 属于基于linux上的小系统. 该小系统的主要功能是对主系统的更新和维护. 但由于其功能单一,无法满足TV上变化多端的需求, 所以, 我们进行了二次开发， 作者本人是基于Recovery5.0进行二次开发， 所以，本文也是给予recovery5.0， 进行说明。
二次开发主要涉及的模块和其开发理由如下:

* 输入系统二次开发: 因为遥控器扫描码的不规范导致需要能通过device控制键值的映射.
* 输出系统二次开发: 因为运营商不同的UI需求和中文字符的要求导致UI能快速定制和更改文字的功能.
* 网络下载模块: 通过网络下载恢复包对主系统进行恢复
* 外部存储模块: 支持通过外部储存上的升级包对主系统进行升级/恢复.
* 升级逻辑二次开发: 多包支持并且实现基于块升级的断电保护.
* 编译系统调整: 独立编译recovery, 其代码树结构与主代码树一致.
* 升级包调整: 减小升级包大小

后文将简单介绍二次开发后的recovery的代码和流程图. 最后针对以上二次开发, 详细介绍所改动部分和注意事项.

从代码上, 升级包的结构和信息并不属于recovery的代码, 但归属于升级模块, 后文也将简单介绍.

## <font color="blue"> recovery框架和流程图 </font> ##

![1534164440618_7](recovery5.0详解.assets/1534164440618_7-1534164995298.png)

* recovery系统从功能上分, 主要包含四个进程: recovery, fota, updater 和 voldaemon.
* recovery主进程的主要功能是为其余进程提供稳定的运行环境和基本的功能, 主要提供功能有: 输入输出系统, zip包校验解压, 脚本, 网络初始化和基本的文件系统操作. 该进程与其他进程的通信都是通过socket/管道方式.
* fota进程主要功能是与fota服务器交互并下载恢复包.
* updater进程来自升级包, 是升级脚本的解释程序, 主要功能是执行升级脚本完成对系统的修改和升级.
* vol daemon进程主要是管理外部存储, 当前提供从U盘读取升级包/恢复包.

![1534164458539_11](recovery5.0详解.assets/1534164458539_11.png)

1. 初始化log系统. 主要是重定向标准输出错误到指定文件.
2. 初始化分区表. 主要是解析分区表文件,在需要的时候, 可以直接根据请求的路径判断挂载所需要的分区. 比如, 要访问```/data/local/tmp/``` 则可以直接根据该路径挂载data分区.
3. 解析recovery参数. 参数获取根据不同device, 实现不同. TV端从sysinfo获取. 参数列表见recovery对外接口文档.
4. EventHub 是输入模块的基类实现, 其主要功能是遍历linux输入子系统并添加所有touch和keyboard类别的事件, 不监听netlink.
5. 底层API初始化,包括minui下的api和自己实现的用于动画, 进度条和文字初始化.
6. layout xml支持相对坐标和相对布局, 比如: LEFT/TOP/CENTER等. 而坐标可以依据屏幕宽高计算, 比如 SCREENWIDTH / 2 + SCREENHEIGHT / 3, 所以, 在这个阶段, 将所有的相对坐标和相对布局通过计算转换成适合该设备的绝对坐标和布局. 这个阶段包括字符串的更新, 图片的预加载和文字的预处理.
7. 这里的interface, 指```/sys/class/net/eth0``` 或者 ```/sys/class/net/wlan0```. 由于某些内核的原因, 需要等待该节点.
8. 这里是生产者消费者模型, 所以, 消费者线程启动时, 清空消息队列, 避免遗留消息导致UI的行为异常.

![1534164453666_10](recovery5.0详解.assets/1534164453666_10.png)

在UI的实现中是基于xml进行布局, 而每控件(button/text), 也是基于xml的. 所以, 按键被按下的行为, 在xml中用脚本进行控制.
这里的按键消息响应图, 展示的是按键传输到UI的更新过程, 其中enter按下会触发对应的脚本执行. 同样, UI的切换(page/screen 切换), 会触发状态脚本, 比如显示升级完成的界面, 会同时启动重启脚本自动重启.

![1534164440930_8](recovery5.0详解.assets/1534164440930_8.png)

1. 初始化, 参考前文的初始化流程. 在启动升级的情况下, 不会主动初始化网络和外部存储.
2. 参数解析, TV上从sysinfo. android标准从/cache/. 断电引起的从bootloader message获取, 一般在misc分区.
3. 支持主系统将升级包下载到外部存储, 或者直接在主系统插入带升级包的U盘. 这里通过参数区分, 因为参数中包含UUID, 所以即使多个外部存储, 也能找到正确的.具体参数细节参考 recovery的api文档.
4. 此处初始化外部存储数据, 然后根据挂载请求, 挂载指定的分区, 并返回拼接完整的升级包绝对路径.
5. 校验升级包, 公私钥. 私钥计算升级包, 并把摘要信息存在zip文件尾部comments之前的无效信息区. recovery读取该摘要信息, 并计算有效数据hash, 通过公钥进行校验. 校验失败则退出重启. 这里, recovery内存放的公钥跟openssl的公钥不一样, 是私有预处理的格式, 当前有3个版本.
6. 升级脚本的解释器, 存放在zip包的```META-INF/com/google/android/update-binary```, 所以可以做到添加新需求时, 只动升级包.
7. 父子进程, 基于管道通信. 通信内容当前只涉及UI更新, 不涉及具体功能.父进程等待子进程退出, 并检查子进程的退出码, 从而判断升级结果.

![1534164440273_5](recovery5.0详解.assets/1534164440273_5.png)

与上面recovery的升级流程图类似, 这幅图是描述iploader模块的工作流程.

1. 初始化, 参考前文的初始化流程. 在启动升级的情况下, 不会主动初始化网络和外部存储.
2. 参数解析, TV上从sysinfo. android标准从/cache/. 断电引起的从bootloader message获取, 一般在misc分区.
3. 判断参数, 是文件路径, 还是U盘信息或者是URL, 如果是URL, 则启动dhcp获取网络.
4. 启动下载程序. 父子进程, 管道通信. fotaclient会从iploader/fota服务器下载升级包到tmpfs. 通信内容涉及到UI更新和下载成功与否的结果.
5. 校验升级包, 公私钥. 私钥计算升级包, 并把摘要信息存在zip文件尾部comments之前的无效信息区. recovery读取该摘要信息, 并计算有效数据hash, 通过公钥进行校验. 校验失败则退出重启. 这里, recovery内存放的公钥跟openssl的公钥不一样, 是私有预处理的格式, 当前有3个版本.
6. 升级脚本的解释器, 存放在zip包的META-INF/com/google/android/update-binary, 所以可以做到添加新需求时, 只动升级包.
7. 父子进程, 基于管道通信. 通信内容当前只涉及UI更新, 不涉及具体功能.父进程等待子进程退出, 并检查子进程的退出码, 从而判断升级结果.
    <br>
    <br>

Android标准的升级包按照升级方式分为两种, 一种是基于文件升级, 一种是基于块升级. 而按照升级形式分为全量升级和增量升级. 全量升级与增量升级的差异主要集中在升级脚本中, 包结构基本无差异.
<br>
<br>
下面是基于文件升级的包内容, system下面的数据以文件为单位存在.

```
Path = update.zip
Type = zip
Comment = signed by SignApk

   Date      Time    Attr   Name
------------------- ----- ------------------------
2008-02-29 02:33:46 .....  META-INF/CERT.RSA
2008-02-29 02:33:46 .....  META-INF/CERT.SF
2008-02-29 02:33:46 .....  META-INF/MANIFEST.MF
2008-02-29 02:33:46 .....  META-INF/com/android/metadata
2008-02-29 02:33:46 .....  META-INF/com/android/otacert
2008-02-29 02:33:46 .....  META-INF/com/google/android/update-binary
2008-02-29 02:33:46 .....  META-INF/com/google/android/updater-script
2008-02-29 02:33:46 .....  boot.img
2008-02-29 02:33:46 .....  system/
2008-02-29 02:33:46 .....  system/xxx
2008-02-29 02:33:46 .....  system/yyy
------------------- ----- ------------------------
```
<br>
<br>
下面是基于块升级的包内容, system文件全部以二进制数据存在, 以块大小为一个单位.

```
Path = update.zip
Type = zip
Comment = signed by SignApk

   Date      Time    Attr   Name
------------------- ----- ------------------------
2008-02-29 02:33:46 .....  META-INF/CERT.RSA
2008-02-29 02:33:46 .....  META-INF/CERT.SF
2008-02-29 02:33:46 .....  META-INF/MANIFEST.MF
2008-02-29 02:33:46 .....  META-INF/com/android/metadata
2008-02-29 02:33:46 .....  META-INF/com/android/otacert
2008-02-29 02:33:46 .....  META-INF/com/google/android/update-binary
2008-02-29 02:33:46 .....  META-INF/com/google/android/updater-script
2008-02-29 02:33:46 .....  boot.img
2008-02-29 02:33:46 .....  system.new.dat
2008-02-29 02:33:46 .....  system.patch.dat
2008-02-29 02:33:46 .....  system.transfer.dat
------------------- ----- ------------------------
```

<br>
升级包含签名信息的zip格式:
![1534164438172_2](recovery5.0详解.assets/1534164438172_2.png)
校验的有效数据为 `[.ZIP file comment length]` 之前的所有数据(不包含该字段).
<br>


## <font color="blue">二次开发详细说明</font> ##

### <font color="DeepSkyBlue"> 输入系统二次开发 </font> ###

需求:

* 遥控器的扫描码非标准键盘值, 并且不同厂家可能有不同的扫描码定义.
* 未来要支持触屏输入.

流程图:
![1534164440279_6](recovery5.0详解.assets/1534164440279_6.png)

由于初始化是标准的linux输入子系统初始化, 此处不再累述. 输入的初始化, 不监听netlink消息, 所以, 不支持usb键盘热插拔.

主要使用的模型是生产者消费者模型, 按键全部通过注册的回调函数传递给UI.

EventHub类和基础的初始化, 读取函数都属于input的工具类. 该图描述的是按键消息的处理, 实际上管道的右侧包括EventReader都是可以被重新实现从而实现触屏功能.



实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 输出系统二次开发 </font> ###

该模块是改动最大的模块. 因为android原生的UI, 只支持基本的贴图和英文字符, 所有的中文显示都是通过贴图实现的, 并且UI的绘制纯粹通过代码一行行实现的. 而为了应付各种各样的运营商UI的需求, 必须实现通过xml布局recovery的UI, 并且能显示中文. 基本的实现机制参考了android的主系统实现.

UI分为三大类, 工具类(四则运算, 用于将相对坐标转换为适合设备的绝对坐标), 布局解析类(用于解析xml, 包括布局文件, 字符文件和脚本文件), 绘制类(用于图片加载, 文字绘制, 图片绘制, 上色和基于fb的工具函数).

工具类:

* ui_calculator, 简单的四则运算实现, 支持宏, 所以能计算时, 将SCREENWIDTH和SCREENHEIGHT使用设备实际的宽高替换.
* m_list.h 从kernel搞过来的双向链表封装, 相当好用的工具. 双向链表也是UI模块里所有控件的基本组织形式.

下面详细描述UI的初始化, 特别是xml布局的实现和绘图.

首先, recovery中的资源的目录组织形式. 具体包含脚本文件, 各个分辨率图片, 各个分辨率的布局文件, 字体文件和中英文文字文件. 具体内容可查看源码res和device下设备资源文件.

```
res/scripts
res/scripts/common.xml
res/images/720L/battery_progress.png
res/images/720L/battery_charge.png
res/images/720L/battery_empty.png
res/images/720L/progress_empty.png
res/images/720L/progress_fill.png
res/images/720L/icon-menu.png
res/styles/1280x720L/statusbar.xml
res/styles/1280x720L/menu.xml
res/styles/1280x720L/main.xml
res/fonts/DroidSansFallback.ttf
res/string/cn/string.xml
res/string/en/string.xml
```

scripts被解析后是以id为key的映射关系保存到map中.string也是以id为key的映射关系保存到map中. 该实现参照了android的.
字体文件是基于freetype进行解析, 并按需要提取对应字号的文字, 其最终形式是图片, 所以绘制方式是贴图.
布局文件在别解析后, 所有的控件在内存中以一个双向链表保存. 具体看下图:
![1534164459341_12](recovery5.0详解.assets/1534164459341_12.png)

这张图展示了布局文件到双向链表的关系, 可以辅助理解代码. 其中, button控件的text与view控件的text内容不一样的原因是继承. 使用了类似类继承的机制, 存在基本的控件button, 其text存在默认参数. 该图中的xml, 并未使用了scripts的映射关系和string的映射关系.
而png图片则是在生成双向链表过程中直接预加载处理.



实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 网络下载模块 </font> ###
下载模块是fotaclient, 是单独的进程, 由recovery fork并执行, 通过管道通信. 原因是, 网络环境复杂, 避免因为网络环境而导致recovery主程序崩溃. 默认下载模式是断电续传, 所以, 代码中存在逻辑判断本地下载了部分的数据是否为有效数据.

![1534164439501_3](recovery5.0详解.assets/1534164439501_3.png)

1. 这里是请求服务器获取升级包信息的json数据.
2. 从json数据中解析出升级包的url和对应的校验信息
3. 校验升级包和本地已下载部分的包, 判断是否是同一个, 如果否, 则删除本地文件.

这里遇到过一个问题, 因为android5以上的dns请求都是通过netd转发的, 所以, 其bionic的实现有直连和代理两种模式. 但在recover中必须使用直连. 所以, 修改了curl的代码, 参考netd的相关代码, 直接调用bionic接口实现dns的修改和请求. 如果有相关需求, 可以参考dns_test.cpp文件.



实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 外部存储模块 </font> ###
一个简化版的vold. 只支持主动发起, 无法被动通知.
其结构是父子进程, 理由与网络下载一样. 监听netlink, 支持热插拔, 支持插着U盘冷启动.

![1534164441181_9](recovery5.0详解.assets/1534164441181_9.png)

实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 升级逻辑二次开发 </font> ###

需求:
在android上, 并不需要考虑断电的可能, 但是在TV上, 却无法保证用户不会强制断电, 或国情断电, 所以, 在android原有的块设备基础上, 实现了断电保护的功能.

android原生的块升级机制不再详细介绍, 因为之前已经介绍过. 下面一个简单描述. 更新时的基本操作如图.

![1534164440051_4](recovery5.0详解.assets/1534164440051_4.png)

机制：

1. 首先，在生成system分区时，同时生产file_map， 该文件包含system分区中的所有文件列表和其实际数据所保存的块索引号。
2. 基于文件名对2个system分区进行比较。文件名相同的块进行diff， 判断是单纯的块移动（move）（['he', 'llow'] ==> ['h', 'ellow]）, 新增（new），删除（zero）或者是需要diff执行patch操作。
3. 在2的执行过程中， 所有操作有src和tgt， 根据该规则建立块依赖关系图。
4. 基于图形学算法,优化3的依赖关系图， 将被依赖的块优先作为src被执行。
5. 若存在循环依赖的块（blockA =>blockB => blockC => blockA）， 则执行stash命令，预先保存src。
6. 因为可能存在src和tgt有重叠， 所以， 必须全部读取src后，在内存中完成操作并写回tgt。

为了支持断电保护的改动:

* 记录命令的index.
* 所有的stas保存到/cache/stash, 命名规则: stash.index
* 当前命令的src, 保存到/cache/.命名规则: backup.index
* 所有的保存机制, 先写入临时文件, 在通过rename重命名成目标名字. rename是异步原子操作, 需要等待.
* 断电后, 遍历命令, 重新导入stash的数据, 并执行到index位置. 判断src备份, 若存在, 则读取(备份成功), 若不存在, 则继续执行.



实现细节： [请查看源码](#no_permission)。

### <font color="DeepSkyBlue"> 升级包二次开发 </font> ###

需求:
为了减小升级包的大小. 特别是为了支持iploader服务器. 当前只能基于文件升级形式进行二次开发.
<br>
实现:
1. lzma2压缩. system目录下的所有文件全部用zip的STORE方式打包, 用lzma进行压缩, 保证最高压缩率.
2. 全量包优化, 升级包中只存放被修改过的文件, 尽量减小升级包大小.
    <br>
    缺陷:
3. lzma2压缩后, 升级的速度有所下降.
4. 全量包优化后, 无法被作为恢复包, 因为缺少用于恢复系统的有效数据. 并且该优化后的包只能替换全量包, 真正在包的大小上, 无法与增量包的稳定性匹敌.

<br>
包结构变化:
lzma2压缩后的包结构如下
```
Path = update.zip
Type = zip
Comment = signed by SignApk

   Date      Time    Attr   Name
------------------- ----- ------------------------
2008-02-29 02:33:46 .....  META-INF/CERT.RSA
2008-02-29 02:33:46 .....  META-INF/CERT.SF
2008-02-29 02:33:46 .....  META-INF/MANIFEST.MF
2008-02-29 02:33:46 .....  META-INF/com/android/metadata
2008-02-29 02:33:46 .....  META-INF/com/android/otacert
2008-02-29 02:33:46 .....  META-INF/com/google/android/update-binary
2008-02-29 02:33:46 .....  META-INF/com/google/android/updater-script
2008-02-29 02:33:46 .....  boot.lzma
2008-02-29 02:33:46 .....  system.lzma
------------------- ----- ------------------------
```

<br>

实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 多升级包升级</font> ###

简称多包升级， 基本原理是， 每两个版本生成一个增量升级包， 比如ab.zip用于从a版本升级到b版本、bc.zip用于从b版本升级到c版本。 那么如果要从a版本升级到c版本， 只要一次性下载ab.zip和bc.zip 并在recovery中， 一次性完成升级再重启。



可靠性论述：

ab.zip 在执行升级前后会执行系统校验， 同理 bc.zip， 如果细看校验的内容， 会发现ab.zip升级完后的校验内容和哈希值与bc.zip升级之前的校验内容和哈希值一样。则  ab.zip -> bc.zip 必定能升级成功， 而bc.zip的校验确保了升级的可靠性。



实现细节： [请查看源码](#no_permission)。



### <font color="DeepSkyBlue"> 编译系统调整 </font> ###

recovery的编译系统类似主系统编译方式, 也有独立的device. 但是是删除无关代码后, 只用于编译recovery的小系统.
由于各个厂家/运营商的需求或实现不同, 可能出现遥控器/fb或其他相关实现存在差异, 这就需要recovery能支持某些实现被devices的实现覆盖(类似overlay的机制). 该实现, 利用的是静态库的符号搜索规则,和编译器对强弱符号的不同处理方式. 所有被overlay的代码都存在`bootable/recovery/devices/default/`, 代码中的所有全局符号必须申明为弱符号. 设备相关的代码放在对应device目录中, 并将该代码编译为静态库, 所有全局符号必须为强符号. 将该静态库添加到```TARGET_RECOVERY_PRIVATE_LIBRARIES```. 则编译时, 会自动使用设备相关的全局符号, 然后才使用弱符号.
device添加规则:

* 对于一个新硬件, 则必须添加对应的硬件device, 比如 zt5000
* 由于不同运营商或者其他可能引起的相同硬件, 不同device, 则添加对应的设备, 比如 zt5000_oon
* 如果bsp是单独的git仓库, 并且不包含可编译的Android.mk, 则直接将该仓库添加到vendor目录下. 否则, 将bsp拷贝到device下. 参考zt5000_oon和zt5000_von
* 有通用拷贝变量`RECOVERY_DEVICE_COPY_FILES`, 不止是拷贝库, bsp, 也可以是设备相关资源文件. 从而避免recovery因为资源文件越来越大.



