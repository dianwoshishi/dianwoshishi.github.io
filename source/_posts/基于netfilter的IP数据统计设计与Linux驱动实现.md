---
title:      基于netfilter的IP数据统计设计
categories:
    - 开发
tags:
    - Linux
    - netfilter
    - 内核
---


# Table of Contents

1.  [背景](#orgab76e7a)
2.  [IP信息统计](#org02ac451)
    1.  [统计信息设计](#org62d4d73)
    2.  [存储数据结构](#org44f97b2)
3.  [Linux驱动](#orgde188bf)
    1.  [网络型驱动设备](#orgc0bb933)
    2.  [字符型设备](#org9e48264)
    3.  [用户代码](#org8ee7f64)
4.  [总结](#org3f4753d)
    1.  [Linux 驱动](#org01bad05)
    2.  [Linux内核](#orgd1e6a5e)
    3.  [其他](#org4c6ff33)
5.  [参考资料](#orgfe8069d)



<a id="orgab76e7a"></a>

# 背景

当今社会，没有都有自己的信息处理设备，如手机、计算机甚至可能是路由器。在使用这些设备的时候，我们想知道的一件事就是，我的电脑和那些设备有过通信，通信情况怎么样，以便在网络出现问题，如拥塞，或是自己主机被黑客控制出现异常数据的时候，能够通过上述统计信息快速定位问题所在。因此本文通过Linux驱动中的netfilter对IP数据报中的IP信息进行统计，通过字符型驱动实现用户态查看统计信息，达到了统计主机通信的目的，为进一步做好异常处理打下了基础。


<a id="org02ac451"></a>

# IP信息统计


<a id="org62d4d73"></a>

## 统计信息设计

统计对象为源IP地址，信息内容目前设计为：IP出现频次，最后一个IP数据包出现时的时间戳。

    typedef struct IPData{
      int timestamp;
      int count
    }ipdata;


<a id="org44f97b2"></a>

## 存储数据结构

由于在Linux Kernel中没有C++的set，map等数据结构，因此使用其提供的红黑树实现IP信息的快速存储和读取。其中红黑树节点的信息如下所示：
```c
       typedef struct roc_node_s
    {
        struct rb_node node;
        void *ctx;
        int key;
        ipdata ipcount;
    }roc_node_t;
```
红黑树的实现使用Linux Kernel自带的rbtree数据结构，头文件为：

    #include <linux/rbtree.h>

红黑树插入，删除等代码参考链接为：<https://blog.csdn.net/chn475111/article/details/52594457>.
```c
    /**
     * filename: my_rbtree.h
     * @author lijk@.infosec.com.cn
     * @version 0.0.1
     * @date 2016-9-20 11:52:06
     */
    #include <linux/string.h>
    #include <linux/rbtree.h>
    typedef struct IPData{
      int timestamp;
      int count
    }ipdata;
    typedef struct roc_node_s
    {
        struct rb_node node;
        void *ctx;
        int key;
        ipdata ipcount;
    }roc_node_t;
    
    typedef void (*roc_cb)(void*);
    
    roc_node_t* roc_search(struct rb_root *root, int key)
    {
        struct rb_node *node = root->rb_node;
        while(node)
        {
            roc_node_t *data = rb_entry(node, roc_node_t, node);
            int result = key - data->key;
    
            if (result < 0)
                node = node->rb_left;
            else if (result > 0)
                node = node->rb_right;
            else
                return data;
        }
        return NULL;
    }
    
    int roc_insert(struct rb_root *root, roc_node_t *data)
    {
        struct rb_node **new = &(root->rb_node), *parent = NULL;
        while(*new)
        {
            roc_node_t *this = rb_entry(*new, roc_node_t, node);
            int result = data->key - this->key;
    
            parent = *new;
            if (result < 0)
                new = &((*new)->rb_left);
            else if (result > 0)
                new = &((*new)->rb_right);
            else
                return 0;
        }
    
        rb_link_node(&data->node, parent, new);
        rb_insert_color(&data->node, root);
    
        return 1;
    }
    
    void roc_erase(struct rb_root *root, int key, roc_cb cb)
    {
        roc_node_t *data = roc_search(root, key);
        if(data)
        {
            rb_erase(&data->node, root);
            RB_CLEAR_NODE(&data->node);
            if(cb) cb(data);
        }
    }
    
    void roc_destroy(struct rb_root *root, roc_cb cb)
    {
        roc_node_t *pos = NULL;
        struct rb_node *node = NULL;
        while((node = rb_first(root)))
        {
            pos = rb_entry(node, roc_node_t, node);
        #ifdef _DEBUG
            sprintf(message, "key = %d\n", pos->key);
        #endif
            rb_erase(&pos->node, root);
            RB_CLEAR_NODE(&pos->node);
            if(cb) cb(pos);
        }
    }
    
    void roc_dump(struct rb_root *root)
    {
        struct rb_node *node = NULL;
      int sip, count, timestamp;
      //printk("roc_dump");
        memset(message, 0, MAX_SIZE);
        for(node = rb_first(root); strlen(message) < MAX_SIZE && node != NULL; node = rb_next(node)){
    
      sip = (unsigned int)rb_entry(node, roc_node_t, node)->key ;   
      count = (unsigned int)rb_entry(node, roc_node_t, node)->ipcount.count ;   
      timestamp = (unsigned int)rb_entry(node, roc_node_t, node)->ipcount.timestamp ;  
      sprintf(message, "%s%d.%d.%d.%d|%d|%d,",message, NIPQUAD( sip), count, timestamp);
          //printk(message);
        }
    }
    
    void roc_free(void *ptr)
    {
        roc_node_t *node = (roc_node_t*)ptr;
        if(node)
        {
            if(node->ctx) kfree(node->ctx);
            kfree(node);
        }
    }
    
    int test(int argc, char const *argv[])
    {
        struct rb_root root = RB_ROOT;
    
        int loop = 0;
        roc_node_t *node = NULL;
        for(loop = 0; loop < 100; loop ++)
        {
            node = (roc_node_t*)kmalloc(sizeof(roc_node_t), GFP_KERNEL );
            if(node == NULL)
                break;
            node->ctx = NULL;
            node->key = loop;
            roc_insert(&root, node);
        }
    
    #if 0
        for(loop = 0; loop < 100; loop ++)
            roc_erase(&root, loop, roc_free);
    #endif
    
        roc_dump(&root);
        roc_destroy(&root, roc_free);
        return 0;
    }

```
<a id="orgde188bf"></a>

# Linux驱动

考虑在内核实现的原因是目前Linux相关设备非常多，可能具有一定的参考价值和移植性。
笔者的内核环境为：

      uname -r
    4.15.0-142-generic


<a id="orgc0bb933"></a>

## 网络型驱动设备

netfilter的相关参考资料为：Linnux5.0.0下，基于Netlink与NetFilter对本机数据包进行筛选监控,<https://blog.csdn.net/qq_40758751/article/details/105117750> , netfilter数据包过滤, <https://blog.csdn.net/specialsun/article/details/84695519>
因为本文为源Ip数据包信息统计，所以netfilter hook的层级在NF<sub>INET</sub><sub>LOCAL</sub><sub>IN</sub>.
Hook 函数为filter<sub>http</sub>(忽略函数名，粘贴过来，不想改了).


<a id="org9e48264"></a>

## 字符型设备

内核态数据在用户态访问需要通过字符型设备驱动进行。因此建立一个字符型设备/dev/IPDataSet 使得用户态能够访问内核 态的数据信息。
参考资料：ubuntu 添加字符设备驱动程序, <https://blog.csdn.net/ARAFATms/article/details/79397800>
因为上述驱动需要自己手动添加字符设备，所以通过以下方法自动添加设备节点。
参考资料：linux驱动：自动创建设备节点, <https://blog.csdn.net/u012247418/article/details/83684029>

    // filename: filter_ip.c
    #ifndef __KERNEL__
    #define __KERNEL__
    #endif  /* __KERNEL__ */
    
    #include <linux/module.h>
    #include <linux/init.h>
    #include <linux/types.h>
    #include <linux/string.h>
    //#include <asm/uaccess.h>
    #include <linux/netdevice.h>
    #include <linux/netfilter_ipv4.h>  // ip4 netfilter,ipv6则需引入相应 linux/netfilter_ipv6.h
    #include <linux/ip.h>
    #include <linux/tcp.h>
    #include <linux/sched.h>
    #include "linux/kernel.h"
    #include "linux/fs.h"
    #include "linux/errno.h"
    #include "linux/uaccess.h"
    #include "linux/kdev_t.h"
    #include <linux/device.h>
    #include <linux/time.h>
    
    #define NIPQUAD(addr) \  
    ((unsigned char *)&addr)[0], \  
    ((unsigned char *)&addr)[1], \  
    ((unsigned char *)&addr)[2], \  
    ((unsigned char *)&addr)[3]  
    
    #define MAX_SIZE 1024 * 1024 * 8
    char message[MAX_SIZE] = "";  //打开设备时会显示的消息
    #include "my_rbtree.h"
    
    struct rb_root root = RB_ROOT;
    int insert(int key, int timestamp)
    {
    
      roc_node_t *node = NULL;
      node = roc_search(&root, key);
      if(node != NULL) {
        node->ipcount.count++;
        node->ipcount.timestamp = timestamp;
        return 1;
      }
      node = (roc_node_t*)kmalloc(sizeof(roc_node_t), GFP_KERNEL );
      node->ctx = NULL;
      node->key = key;
      node->ipcount.count = 1;
      node->ipcount.timestamp = timestamp;
      return roc_insert(&root, node);
    
    }
    
    struct timeval time;
    // 过滤http数据包
    unsigned int filter_http(char *type,struct sk_buff *pskb)
    {
      __be32 sip,dip;
      int retval = NF_ACCEPT;
      int ret, ms;
      struct sk_buff *skb = pskb;
    
      struct iphdr *iph = ip_hdr(skb);  // 获取ip头
    
      sip = iph->saddr;  
      dip = iph->daddr;  
      //printk("Packet for source address: %d.%d.%d.%d destination address: %d.%d.%d.%d\n", NIPQUAD(sip), NIPQUAD(dip));  
    
      //sprintf(message, "Packet for source address: %d.%d.%d.%d destination address: %d.%d.%d.%d\n", NIPQUAD(sip), NIPQUAD(dip));


      do_gettimeofday(&time);  /*第一次去获取时间*/  ms = time.tv_sec * 1000 + time.tv_usec / 1000;  ret = insert(sip, ms);  //if(ret == 1){	  roc_dump(&root);  printk(message);  //}  return retval;}


    unsigned int NET_HookLocalIn(void *priv,     struct sk_buff *pskb,     const struct nf_hook_state *state){  return filter_http("in",pskb);}


    unsigned int NET_HookLocalOut(void *priv,     struct sk_buff *pskb,     const struct nf_hook_state *state){  //return filter_http("out",pskb);  return NF_ACCEPT;}



    unsigned int NET_HookPreRouting(void *priv,     struct sk_buff *pskb,     const struct nf_hook_state *state){  return NF_ACCEPT;}

 


    unsigned int NET_HookPostRouting(void *priv,     struct sk_buff *pskb,     const struct nf_hook_state *state){  return NF_ACCEPT;}


    unsigned int NET_HookForward(void *priv,     struct sk_buff *pskb,     const struct nf_hook_state *state){  return NF_ACCEPT;}


    // 钩子数组static struct nf_hook_ops net_hooks[] = {  {    .hook 		= NET_HookLocalIn,		// 发往本地数据包    .pf			= PF_INET,    .hooknum	=	NF_INET_LOCAL_IN,    .priority	= NF_IP_PRI_FILTER-1,  },  {    .hook 		= NET_HookLocalOut,		// 本地发出数据包    .pf			= PF_INET,    .hooknum	=	NF_INET_LOCAL_OUT,    .priority	= NF_IP_PRI_FILTER-1,  },  {    .hook 		= NET_HookForward,		// 转发的数据包    .pf			= PF_INET,    .hooknum	=	NF_INET_FORWARD,    .priority	= NF_IP_PRI_FILTER-1,  },  {    .hook		= NET_HookPreRouting,	// 进入本机路由前	    .pf			= PF_INET,				    .hooknum	= NF_INET_PRE_ROUTING,		    .priority	= NF_IP_PRI_FILTER-1,		  },  {    .hook		= NET_HookPostRouting,	// 本机发出包经路由后	    .pf			= PF_INET,				    .hooknum	= NF_INET_POST_ROUTING,		    .priority	= NF_IP_PRI_FILTER-1,		  },};


    int my_open(struct inode *inode, struct file *file);int my_release(struct inode *inode, struct file *file);ssize_t my_read(struct file *file, char __user *user, size_t t, loff_t *f);ssize_t my_write(struct file *file, const char __user *user, size_t t, loff_t *f);char* devName = "IPDataSet";//设备名struct file_operations pStruct ={ open:my_open,      release:my_release,      read:my_read,      write:my_write, };//打开int my_open(struct inode *inode, struct file *file){  printk("open lgsDrive OK!\n");  try_module_get(THIS_MODULE);  return 0;}//关闭int my_release(struct inode *inode, struct file *file){  printk("Device released!\n");  module_put(THIS_MODULE);  return 0;}


    //读设备里的信息ssize_t my_read(struct file *file, char __user *user, size_t t, loff_t *f){  roc_dump(&root);  if(copy_to_user(user,message,t))  {    return -2;  }  return sizeof(message);}//向设备里写信息ssize_t my_write(struct file *file, const char __user *user, size_t t, loff_t *f){  if(copy_from_user(message,user,t))  {    return -3;  }  return sizeof(message);}


    static struct class *drv_class = NULL;int major = 0;//设备号static int __init nf_init(void) {  int ret = 0;  //char device  major = register_chrdev(0, "ipdataset_drv", &pStruct);  drv_class = class_create(THIS_MODULE, "ipdataset_drv");  device_create(drv_class, NULL, MKDEV(major, 0), NULL, devName);  //	ret = register_chrdev(0, devName, &pStruct);  //	if (ret < 0)  //	{  //		printk("failed to register_chrdev.\n");  //		return -1;  //	}  //	else  //	{  //		printk("the lgsDrive has been registered!\n");  //		printk("id: %d\n", ret);  //		device_num = ret;  //   //		return 0;  //	}  //net device  ret = nf_register_net_hook(&init_net, net_hooks);  //ret = nf_register_hooks(net_hooks,ARRAY_SIZE(net_hooks));	// 安装钩子  if(ret)  {    printk(KERN_ERR "register hook failed\n");    return -1;  }  printk("Start...\n");  return 0;}void close(void){  roc_destroy(&root, roc_free);}static void __exit nf_exit(void){  close();  unregister_chrdev(major, "ipdataset_drv");  device_destroy(drv_class, MKDEV(major, 0));  class_destroy(drv_class);  //unregister_chrdev(device_num, devName);


      nf_unregister_net_hook(&init_net, net_hooks);  //nf_unregister_hooks(net_hooks,ARRAY_SIZE(net_hooks));	// 卸载钩子  printk("Exit...\n");}



    module_init(nf_init);module_exit(nf_exit);

 


    MODULE_LICENSE("Dual BSD/GPL");MODULE_AUTHOR("dianwoshishi");MODULE_DESCRIPTION("Netfilter IP Statistic");MODULE_VERSION("1.0.1");MODULE_ALIAS("Netfilter 01");


<a id="org8ee7f64"></a>

## 用户代码

上述字符型设备创建了一个字符节点为：/dev/IPDataSet， 在用户态程序中，我们通过Linux编程中提供的read函数对驱动中的数据message进行读取。
代码如下：

       #include <stdio.h>#include <sys/types.h>#include <sys/stat.h>#include <fcntl.h>#define MAX_SIZE 1024 char message[MAX_SIZE] ;  //打开设备时会显示的消息int main(int num, char *arg[]){    if(2 != num){        printf("Usage: %s /dev/IPDataSet\n", arg[0]);        return -1;    }    int fd = open(arg[1], O_RDWR);    if(0 > fd){        perror("open");        return -1;    }    int ret = read(fd, message, MAX_SIZE);    printf("read: ret = %d. %s\n", ret, message);    memset(message, 0, MAX_SIZE);    ret = write(fd, message, MAX_SIZE);    printf("write: ret = %d.\n", ret);    close(fd);    return 0;}


<a id="org3f4753d"></a>

# 总结


<a id="org01bad05"></a>

## Linux 驱动

熟悉Linux驱动的编写流程。 了解了Linux内核代码与用户代码的不同，比较明显的就是缺少了类似C++ STL类似的好用的库，只能使用类似红黑树（rbtree)这样的数据结构来做一些set的操作，需要对红黑树有一定的了解。
网络设备驱动和字符型设备驱动的编写结构都差不多，但是目前也是一知半解，尤其是一些简单操作之外的特性还不了解，例如加锁？多线程？不知道


<a id="orgd1e6a5e"></a>

## Linux内核

Linux内核的设计模式还是比较令人佩服的，虽然不懂全貌，但是也能从局部出发，贡献一些力量。再一次感受到了设计的魅力。


<a id="org4c6ff33"></a>

## 其他

一定要在虚拟机中编写、测试驱动，不知道有什么错出现，你就要重启你的电脑，boring！


<a id="orgfe8069d"></a>

# 参考资料

linux驱动编写（总结篇）,<https://blog.csdn.net/feixiaoxing/article/details/79913476?spm=1001.2014.3001.5506>
智能路由器设备流量、网速统计及上下线提醒（基于netfilter编程）,<https://blog.csdn.net/u012819339/article/details/50513387?spm=1001.2014.3001.5506>
利用Linux内核模块Netfilter hook UDP报文, <https://blog.csdn.net/qq_41791640/article/details/104933006?spm=1001.2014.3001.5506>
Netfilter的使用和实现, <https://blog.csdn.net/zhangskd/article/details/22678659?spm=1001.2014.3001.5506>

